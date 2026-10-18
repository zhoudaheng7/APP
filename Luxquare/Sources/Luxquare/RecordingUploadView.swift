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
    @State private var message: String?
    var recordingModule: WorkbenchModule? { model.availableModules.first { $0.moduleID == "recordings" } }
    var body: some View {
        NavigationStack {
            Form {
                Section("上传到录音总结") {
                    TextField("录音标题", text: $title).font(.body)
                    Text("上传账号：\(model.user?.displayName ?? "尚未登录")").font(.subheadline)
                    Text("原始录音继续保存在本机。上传后由录音总结模块按现有权限处理。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message).font(.subheadline).textSelection(.enabled) } }
                Section {
                    if finished {
                        Button("完成") { dismiss() }
                    } else {
                        Button { Task { await upload() } } label: {
                            HStack { Text(uploading ? "正在上传…" : "确认上传"); Spacer(); if uploading { ProgressView() } }
                        }.disabled(uploading || model.user == nil || recordingModule == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("先连接录音总结模块") { onConnect(); dismiss() }.disabled(uploading)
                    }
                }
            }
            .navigationTitle("上传录音").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(uploading) } }
            .interactiveDismissDisabled(uploading)
        }
    }
    private func upload() async {
        guard let user = model.user, let origin = recordingModule?.origin else { return }
        guard let owner = NativeRecorder.shared.accountScope(for: file) else { message = ClientError.unsignedDraft.localizedDescription; return }
        guard owner == user.identityID else { message = ClientError.identityChanged.localizedDescription; return }
        uploading = true; message = nil; defer { uploading = false }
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
            request.setValue(title.addingPercentEncoding(withAllowedCharacters: safe), forHTTPHeaderField: "X-Recording-Title")
            request.setValue(TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: safe), forHTTPHeaderField: "X-Timezone")
            guard NativeRecorder.shared.accountScope(for: file) == model.user?.identityID else { throw ClientError.identityChanged }
            sent = true
            let (_, response) = try await model.client.upload(file: file, to: request)
            guard (200...299).contains(response.statusCode) else { sent = false; throw ClientError.status(response.statusCode) }
            finished = true; message = "服务器已接收录音，可到录音总结模块查看处理进度。"
        } catch {
            message = sent ? "上传结果尚未确认。本机文件仍在；请先到录音总结查看，避免重复提交。" : error.localizedDescription
        }
    }
}
