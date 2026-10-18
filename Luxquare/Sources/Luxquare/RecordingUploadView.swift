import CryptoKit
import Foundation
import SwiftUI

struct UploadRecording: Identifiable { let id = UUID(); let url: URL }

@MainActor
struct RecordingUploadView: View {
    let file: URL
    @ObservedObject var model: WorkbenchModel
    var onConnect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = "会议录音"
    @State private var uploading = false
    @State private var finished = false
    @State private var unconfirmed = false
    @State private var confirmRetry = false
    @State private var message: String?
    private struct PendingUpload: Codable { let title: String }
    private var pendingKey: String {
        let scope = NativeRecorder.shared.accountScope(for: file) ?? "anonymous"
        let digest = SHA256.hash(data: Data((scope + "|" + file.lastPathComponent).utf8))
        return "recordingUploadPending." + digest.map { String(format: "%02x", $0) }.joined()
    }
    var recordingModule: WorkbenchModule? { model.availableModules.first { $0.moduleID == "recordings" } }
    var body: some View {
        NavigationStack {
            Form {
                Section("上传到录音总结") {
                    TextField("录音标题", text: $title).font(.body).disabled(uploading || unconfirmed || finished)
                    Text("上传账号：\(model.user?.displayName ?? "尚未登录")").font(.subheadline)
                    Text("原始录音继续保存在本机。上传后由录音总结模块按现有权限处理。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message).font(.subheadline).textSelection(.enabled) } }
                Section {
                    if finished {
                        Button("完成") { dismiss() }
                    } else if unconfirmed {
                        Button("到录音总结核对") { onConnect(); dismiss() }.disabled(uploading)
                        Button("已核对未保存，重试同一录音") { confirmRetry = true }.disabled(uploading)
                    } else {
                        Button { Task { await upload() } } label: {
                            HStack { Text(uploading ? "正在上传…" : "确认上传"); Spacer(); if uploading { ProgressView() } }
                        }.disabled(uploading || model.user == nil || recordingModule == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("先连接录音总结模块") { onConnect(); dismiss() }.disabled(uploading)
                    }
                }
            }
            .task { restorePending() }
            .confirmationDialog("确认服务器没有这段录音？", isPresented: $confirmRetry, titleVisibility: .visible) {
                Button("重试同一录音") { Task { await upload() } }
                Button("取消", role: .cancel) {}
            } message: { Text("将重传原文件和原标题。服务器会按当前账号和音频内容识别重复录音。") }
            .navigationTitle("上传录音").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(uploading) } }
            .interactiveDismissDisabled(uploading)
        }
    }
    private func restorePending() {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let pending = try? JSONDecoder().decode(PendingUpload.self, from: data) else { return }
        title = pending.title; unconfirmed = true
        message = "上次上传结果尚未确认。本机录音仍在，请先到录音总结核对。"
    }
    private func upload() async {
        guard !uploading, let user = model.user, let origin = recordingModule?.origin else { return }
        guard let owner = NativeRecorder.shared.accountScope(for: file) else { message = ClientError.unsignedDraft.localizedDescription; return }
        guard owner == user.identityID else { message = ClientError.identityChanged.localizedDescription; return }
        let uploadTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uploadTitle.isEmpty, uploadTitle.count <= 160 else { message = "标题请控制在1至160个字。"; return }
        uploading = true; message = nil; defer { uploading = false }
        let key = pendingKey
        var sent = false
        do {
            let info = try file.resourceValues(forKeys: [.fileSizeKey])
            guard let size = info.fileSize, size > 0, size <= 200 * 1024 * 1024 else {
                message = "文件超出录音模块的200MB上限，请保留本机录音后分段导入。"; return
            }
            let (meData, meResponse) = try await model.client.response(for: URLRequest(url: origin.appendingPathComponent("api/me")))
            guard meResponse.statusCode == 200 else { throw ClientError.status(meResponse.statusCode) }
            guard let me = try JSONSerialization.jsonObject(with: meData) as? [String: Any], me["identity_id"] as? String == user.identityID,
                  model.user?.identityID == user.identityID else { throw ClientError.identityChanged }
            let target = origin.appendingPathComponent("api/recordings/audio")
            guard let csrf = await model.client.cookie(named: "__Host-recordings_csrf", for: target) else { throw ClientError.status(401) }
            var request = URLRequest(url: target)
            request.httpMethod = "POST"; request.timeoutInterval = 900
            request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            request.setValue(csrf, forHTTPHeaderField: "X-Recordings-CSRF")
            var safe = CharacterSet.urlQueryAllowed; safe.remove(charactersIn: "+&=\r\n")
            request.setValue(uploadTitle.addingPercentEncoding(withAllowedCharacters: safe), forHTTPHeaderField: "X-Recording-Title")
            request.setValue(TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: safe), forHTTPHeaderField: "X-Timezone")
            guard NativeRecorder.shared.accountScope(for: file) == model.user?.identityID else { throw ClientError.identityChanged }
            UserDefaults.standard.set(try JSONEncoder().encode(PendingUpload(title: uploadTitle)), forKey: key)
            sent = true
            let (data, response) = try await model.client.upload(file: file, to: request)
            if (400...499).contains(response.statusCode) {
                sent = false; unconfirmed = false
                UserDefaults.standard.removeObject(forKey: key)
                throw ClientError.status(response.statusCode)
            }
            guard (200...299).contains(response.statusCode),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let recordingID = result["recording_id"] as? String, !recordingID.isEmpty else { throw ClientError.invalidResponse }
            UserDefaults.standard.removeObject(forKey: key)
            unconfirmed = false; finished = true
            message = "服务器已接收录音，可到录音总结模块查看处理进度。"
        } catch {
            if sent {
                unconfirmed = true
                message = "上传结果尚未确认。本机文件仍在；请先到录音总结核对，再决定是否重试。"
            } else { message = error.localizedDescription }
        }
    }
}
