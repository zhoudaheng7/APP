import Combine
import CryptoKit
import Foundation
import SwiftUI
import UIKit
import WebKit

struct BrowserShareItem: Identifiable {
    let url: URL
    let id: UUID
    init(url: URL, id: UUID = UUID()) { self.url = url; self.id = id }
}

@MainActor
final class WorkbenchBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @Published private(set) var title = "工作台"
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published var errorMessage: String?
    @Published var shareFile: BrowserShareItem?

    let webView: WKWebView
    private weak var model: WorkbenchModel?
    private let initialURL: URL
    private var observations: [NSKeyValueObservation] = []
    private var subscriptions = Set<AnyCancellable>()
    private var scriptProxy: BrowserScriptProxy?
    private let nativeLocation = NativeLocationService()
    private var pendingLocation: BrowserLocationRequest?
    private var downloads: [ObjectIdentifier: BrowserDownloadContext] = [:]
    private static let bridgeName = "luxquareNativeCore"
    private static let bridgeWorld = WKContentWorld.world(name: "LuxquareNativeDeviceBridge")

    init(url: URL, model: WorkbenchModel) {
        initialURL = url
        self.model = model
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.accessibilityIdentifier = "workbench.browser.webview"
        // No Feishu UA impersonation, certificate override, zoom, fixed viewport, or cookie export.
        installBridge(in: controller, origins: model.businessOrigins)
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.estimatedProgress
                Task { @MainActor [weak self] in self?.progress = value }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.canGoBack
                Task { @MainActor [weak self] in self?.canGoBack = value }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.title
                Task { @MainActor [weak self] in
                    if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self?.title = String(value.prefix(120)) }
                }
            }
        ]
        nativeLocation.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            Task { @MainActor [weak self] in self?.finishLocation(error: message) }
        }.store(in: &subscriptions)
        if model.permitsWebNavigation(url) { webView.load(URLRequest(url: url)) }
        else { errorMessage = "这个页面尚未在工作台开放，请从应用目录重新进入。" }
    }

    func reload() {
        errorMessage = nil
        if webView.url != nil { webView.reload() }
        else if model?.permitsWebNavigation(initialURL) == true { webView.load(URLRequest(url: initialURL)) }
        else { errorMessage = "这个页面尚未在工作台开放，请从应用目录重新进入。" }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        errorMessage = nil
        webView.goBack()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { decisionHandler(.cancel); return }
        let isTopNavigation = navigationAction.targetFrame?.isMainFrame ?? navigationAction.sourceFrame.isMainFrame
        if scheme == "about", url.absoluteString == "about:blank", !isTopNavigation {
            decisionHandler(.allow); return
        }
        if scheme == "blob", isDownloadURL(url), navigationAction.shouldPerformDownload, isTopNavigation {
            decisionHandler(.download); return
        }
        if ["feishu", "lark"].contains(scheme), isTopNavigation,
           sourceIsAllowed(navigationAction.sourceFrame) {
            decisionHandler(.cancel)
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                if !opened { Task { @MainActor [weak self] in self?.errorMessage = "未能打开飞书，请确认手机已安装飞书后重试。" } }
            }
            return
        }
        guard scheme == "https", url.user == nil, url.password == nil, url.host != nil else {
            if isTopNavigation { errorMessage = "已阻止不受支持或不安全的页面地址。" }
            decisionHandler(.cancel); return
        }
        // Let WebKit/CSP handle HTTPS subframes; do not launch Safari for embedded content.
        guard isTopNavigation else { decisionHandler(.allow); return }
        if model?.permitsWebNavigation(url) == true {
            errorMessage = nil
            if navigationAction.shouldPerformDownload {
                if isDownloadURL(url) { decisionHandler(.download) }
                else { errorMessage = "当前页面不允许直接下载这个文件。"; decisionHandler(.cancel) }
            } else if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
            } else { decisionHandler(.allow) }
        } else {
            decisionHandler(.cancel)
            // Unknown HTTPS destinations open in the system browser, outside the company session.
            UIApplication.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame else { decisionHandler(.allow); return }
        if let response = navigationResponse.response as? HTTPURLResponse {
            if response.statusCode == 401 {
                errorMessage = "企业登录已失效，请返回首页重新登录。"
                if let model { Task { await model.refresh(force: true) } }
                decisionHandler(.allow); return
            }
            if response.statusCode == 403 {
                errorMessage = "当前账号没有这个页面的权限，请联系工作台负责人。"
                decisionHandler(.allow); return
            }
            if response.statusCode >= 400 {
                errorMessage = "页面暂时无法打开，请稍后刷新。"
                decisionHandler(.allow); return
            }
        }
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") {
            if let url = navigationResponse.response.url, isDownloadURL(url) { decisionHandler(.download) }
            else { errorMessage = "当前页面不允许直接下载这个文件。"; decisionHandler(.cancel) }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        finishLocation(error: "页面已切换，请在当前页面重新获取位置。")
        nativeLocation.cancel()
        progress = 0
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress = 1
        canGoBack = webView.canGoBack
        if let model, let url = webView.url, url.originURL == model.baseURL {
            Task { await model.refresh() }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { displayNavigationError(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { displayNavigationError(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        errorMessage = "页面已暂停，点击刷新即可重新打开。"
    }

    private func displayNavigationError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        if nsError.domain == NSURLErrorDomain && [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot].contains(nsError.code) {
            errorMessage = "连接证书暂时无法验证，请联系工作台负责人检查地址与证书。"
        } else { errorMessage = "暂时无法连接此页面，请检查网络后刷新。" }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url,
              navigationAction.sourceFrame.isMainFrame else { return nil }
        if model?.permitsWebNavigation(url) == true { webView.load(navigationAction.request) }
        else if url.scheme == "https", url.user == nil, url.password == nil { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard sourceIsAllowed(frame) else { completionHandler(); return }
        let alert = UIAlertController(title: "页面提示", message: String(message.prefix(1_500)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default) { _ in completionHandler() })
        if !present(alert) { completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard sourceIsAllowed(frame) else { completionHandler(false); return }
        let alert = UIAlertController(title: "请确认", message: String(message.prefix(1_500)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确认", style: .default) { _ in completionHandler(true) })
        if !present(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard sourceIsAllowed(frame) else { completionHandler(nil); return }
        let alert = UIAlertController(title: "页面输入", message: String(prompt.prefix(1_000)), preferredStyle: .alert)
        alert.addTextField { field in field.text = defaultText.map { String($0.prefix(4_096)) }; field.font = .preferredFont(forTextStyle: .body) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确认", style: .default) { [weak alert] _ in completionHandler(alert?.textFields?.first?.text) })
        if !present(alert) { completionHandler(nil) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowed = frame.isMainFrame && isBusinessOrigin(securityOrigin: origin) && model?.user != nil
        decisionHandler(allowed ? .prompt : .deny)
    }

    func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    private func present(_ controller: UIAlertController) -> Bool {
        guard var presenter = webView.window?.rootViewController else { return false }
        while let next = presenter.presentedViewController { presenter = next }
        guard !(presenter is UIAlertController), !presenter.isBeingDismissed else { return false }
        presenter.present(controller, animated: true)
        return true
    }

    private func sourceIsAllowed(_ frame: WKFrameInfo) -> Bool {
        guard frame.isMainFrame, let url = frame.request.url else { return false }
        return model?.permitsWebNavigation(url) == true
    }

    private func isBusinessOrigin(securityOrigin: WKSecurityOrigin) -> Bool {
        guard securityOrigin.protocol == "https" else { return false }
        var components = URLComponents()
        components.scheme = "https"; components.host = securityOrigin.host
        if securityOrigin.port > 0 && securityOrigin.port != 443 { components.port = securityOrigin.port }
        guard let origin = components.url?.originURL?.absoluteString else { return false }
        return model?.businessOrigins.contains(origin) == true
    }

    private func isDownloadURL(_ url: URL) -> Bool {
        guard model?.user != nil else { return false }
        if url.scheme == "https", let origin = url.originURL?.absoluteString { return model?.businessOrigins.contains(origin) == true }
        if url.scheme == "blob", let inner = URL(string: String(url.absoluteString.dropFirst(5))), let origin = inner.originURL?.absoluteString {
            return model?.businessOrigins.contains(origin) == true && webView.url?.originURL?.absoluteString == origin
        }
        return false
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        attach(download, url: navigationAction.request.url)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        attach(download, url: navigationResponse.response.url)
    }

    private func attach(_ download: WKDownload, url: URL?) {
        guard let url, isDownloadURL(url), let identity = model?.user?.identityID else {
            download.cancel { _ in }; return
        }
        downloads[ObjectIdentifier(download)] = BrowserDownloadContext(download: download, identityID: identity)
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let key = ObjectIdentifier(download)
        guard var context = downloads[key], context.identityID == model?.user?.identityID,
              let url = response.url, isDownloadURL(url) else { completionHandler(nil); return }
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Downloads", isDirectory: true)
            let identityDigest = SHA256.hash(data: Data(context.identityID.utf8)).map { String(format: "%02x", $0) }.joined()
            var directory = root.appendingPathComponent(identityDigest, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
            let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            guard free > max(0, response.expectedContentLength) + 64 * 1_024 * 1_024 else { throw NativeCapabilityError.unavailable("手机空间不足，暂时无法保存这个文件。") }
            let baseName = (suggestedFilename.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
            let cleaned = baseName.components(separatedBy: .controlCharacters).joined().replacingOccurrences(of: ":", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "download" : String(cleaned.prefix(120))
            let destination = directory.appendingPathComponent(UUID().uuidString.lowercased() + "-" + filename)
            context.destination = destination
            downloads[key] = context
            completionHandler(destination)
        } catch {
            errorMessage = error is NativeCapabilityError ? error.localizedDescription : "未能准备本机下载目录，请检查手机空间。"
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let context = downloads.removeValue(forKey: ObjectIdentifier(download)), let url = context.destination else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { errorMessage = "下载文件未能保存，请重试。"; return }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        guard context.identityID == model?.user?.identityID else {
            errorMessage = "下载期间身份已变化，文件已留在原账号的本机下载目录。"; return
        }
        shareFile = BrowserShareItem(url: url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let context = downloads.removeValue(forKey: ObjectIdentifier(download))
        if let url = context?.destination, FileManager.default.fileExists(atPath: url.path) {
            // Only this failed download's new partial file is removed; completed files remain.
            try? FileManager.default.removeItem(at: url)
        }
        let nsError = error as NSError
        if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled { errorMessage = "文件下载未完成，请检查网络或手机空间后重试。" }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        guard let context = downloads[ObjectIdentifier(download)], context.identityID == model?.user?.identityID,
              let url = request.url, isDownloadURL(url) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    private func installBridge(in controller: WKUserContentController, origins: Set<String>) {
        let proxy = BrowserScriptProxy(browser: self)
        scriptProxy = proxy
        controller.add(proxy, contentWorld: Self.bridgeWorld, name: Self.bridgeName)
        let data = (try? JSONSerialization.data(withJSONObject: Array(origins).sorted())) ?? Data("[]".utf8)
        let allowedOrigins = String(data: data, encoding: .utf8) ?? "[]"
        let guardPrefix = "if (!(\(allowedOrigins)).includes(location.origin) || window !== window.top) return;"
        let pageScript = """
        (() => {
          \(guardPrefix)
          if (window.LuxquareNative) return;
          const pending = new Map();
          window.addEventListener('luxquare-native-response', event => {
            if (typeof event.detail !== 'string' || event.detail.length > 8000) return;
            try {
              const response = JSON.parse(event.detail);
              const entry = pending.get(response.id);
              if (!entry) return;
              clearTimeout(entry.timeout); pending.delete(response.id);
              if (response.error) entry.reject(new Error(response.error));
              else entry.resolve(response.payload);
            } catch (_) {}
          });
          const getLocation = () => new Promise((resolve, reject) => {
            const id = crypto.randomUUID();
            const timeout = setTimeout(() => { pending.delete(id); reject(new Error('定位未完成，请重试。')); }, 30000);
            pending.set(id, {resolve, reject, timeout});
            window.dispatchEvent(new CustomEvent('luxquare-native-request', {detail: JSON.stringify({id, action: 'getLocation'})}));
          });
          Object.defineProperty(window, 'LuxquareNative', {configurable: false, writable: false,
            value: Object.freeze({capabilities: Object.freeze({version: 1, getLocation: true, recordingBridge: false}), getLocation})});
        })();
        """
        let isolatedScript = """
        (() => {
          \(guardPrefix)
          let lastGesture = -Infinity;
          ['pointerup', 'click', 'keydown'].forEach(name => window.addEventListener(name, event => {
            if (event.isTrusted) lastGesture = performance.now();
          }, true));
          window.addEventListener('luxquare-native-request', event => {
            if (typeof event.detail !== 'string' || event.detail.length > 1000) return;
            let request;
            try { request = JSON.parse(event.detail); } catch (_) { return; }
            if (!request || typeof request.id !== 'string' || !/^[A-Za-z0-9-]{1,80}$/.test(request.id) || request.action !== 'getLocation') return;
            if (performance.now() - lastGesture > 1000) {
              window.dispatchEvent(new CustomEvent('luxquare-native-response', {detail: JSON.stringify({id: request.id, error: '请点击页面按钮后获取位置。'})}));
              return;
            }
            window.webkit.messageHandlers.\(Self.bridgeName).postMessage({id: request.id, action: 'getLocation', userGesture: true});
          });
        })();
        """
        controller.addUserScript(WKUserScript(source: pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        controller.addUserScript(WKUserScript(source: isolatedScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.bridgeWorld))
    }

    fileprivate func receiveNativeMessage(_ message: WKScriptMessage) {
        guard message.name == Self.bridgeName, message.frameInfo.isMainFrame,
              isBusinessOrigin(securityOrigin: message.frameInfo.securityOrigin),
              let identity = model?.user?.identityID,
              let body = message.body as? [String: Any], body.count <= 4,
              let id = body["id"] as? String, id.range(of: "^[A-Za-z0-9-]{1,80}$", options: .regularExpression) != nil,
              let action = body["action"] as? String, action == "getLocation", body["userGesture"] as? Bool == true,
              let origin = message.frameInfo.request.url?.originURL?.absoluteString,
              webView.url?.originURL?.absoluteString == origin else { return }
        guard UIApplication.shared.applicationState == .active else { reply(id: id, error: "请在 App 前台获取位置。"); return }
        guard pendingLocation == nil else { reply(id: id, error: "已有一次定位正在进行，请稍候。"); return }
        pendingLocation = BrowserLocationRequest(id: id, origin: origin, identityID: identity)
        nativeLocation.errorMessage = nil
        nativeLocation.request { [weak self] fix in
            self?.finishLocation(fix: fix)
        }
    }

    private func finishLocation(fix: NativeLocationFix? = nil, error: String? = nil) {
        guard let request = pendingLocation else { return }
        pendingLocation = nil
        guard request.identityID == model?.user?.identityID,
              request.origin == webView.url?.originURL?.absoluteString,
              model?.businessOrigins.contains(request.origin) == true else { return }
        if let error { reply(id: request.id, error: error) }
        else if let fix {
            reply(id: request.id, payload: ["latitude": fix.latitude, "longitude": fix.longitude, "accuracy": fix.accuracy,
                                           "timestamp": fix.measuredAt.timeIntervalSince1970 * 1000,
                                           "provider": "corelocation", "coordinateSystem": "wgs84"])
        }
    }

    private func reply(id: String, payload: [String: Any]? = nil, error: String? = nil) {
        var response: [String: Any] = ["id": id]
        if let payload { response["payload"] = payload }
        if let error { response["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: response), let value = String(data: data, encoding: .utf8) else { return }
        let script = "window.dispatchEvent(new CustomEvent('luxquare-native-response', {detail: JSON.stringify(\(value))}));"
        webView.evaluateJavaScript(script, in: nil, in: Self.bridgeWorld) { _ in }
    }
}

@MainActor
private final class BrowserScriptProxy: NSObject, WKScriptMessageHandler {
    weak var browser: WorkbenchBrowser?
    init(browser: WorkbenchBrowser) { self.browser = browser; super.init() }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { browser?.receiveNativeMessage(message) }
}

private struct BrowserLocationRequest {
    let id: String
    let origin: String
    let identityID: String
}

private struct BrowserDownloadContext {
    let download: WKDownload
    let identityID: String
    var destination: URL?
}

@MainActor
struct WorkbenchWebView: UIViewRepresentable {
    let browser: WorkbenchBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
