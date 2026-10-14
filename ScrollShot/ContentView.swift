import SwiftUI
import Photos
import UserNotifications

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorized = PhotoSaver.isAuthorized
    @State private var showPicker = false
    @State private var busy = false
    @State private var progress = 0.0
    @State private var status = "首次使用，请先允许保存照片。"
    @State private var result: StitchResult?
    @State private var image: UIImage?
    @State private var top = 12.0
    @State private var bottom = 14.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("录屏，留下完整内容。").font(.largeTitle.bold())
                        Text("手机本地去重拼接 · 不上传 · 无会员").font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("开始长图录屏").font(.title2.bold())
                        if !authorized {
                            Button("允许保存到照片", action: requestPhotos).buttonStyle(.borderedProminent)
                        } else if BroadcastPicker.extensionID != nil {
                            HStack {
                                BroadcastPicker().frame(width: 60, height: 60)
                                Text("点系统录屏按钮\n在弹窗中确认开始广播").font(.subheadline)
                            }
                        } else {
                            Text("录屏扩展未安装。签名时必须保留 Broadcast.appex；此安装包目前只能转换已有录屏。").foregroundStyle(.red).font(.subheadline)
                        }
                        Text("切回要保存的聊天或页面，从顶部缓慢向下滚动。结束时点系统的红色录屏按钮，扩展会尝试生成并保存长图。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("测试版：自动保存和签名兼容性尚需实机验证。默认裁掉顶部 12%、底部 14%；长图过长时只保存达到上限前的部分。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("允许完成通知") {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                        }.buttonStyle(.bordered)
                    }.padding().background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("转换已有录屏").font(.title2.bold())
                        Text("也可以选取苹果系统保存的录屏，调整固定栏裁剪后在 App 内处理。").font(.subheadline).foregroundStyle(.secondary)
                        HStack { Text("裁掉顶部"); Slider(value: $top, in: 0...35, step: 1); Text("\(Int(top))%") }
                        HStack { Text("裁掉底部"); Slider(value: $bottom, in: 0...35, step: 1); Text("\(Int(bottom))%") }
                        Button(busy ? "正在处理…" : "选择录屏并生成长图") { showPicker = true }
                            .buttonStyle(.borderedProminent).disabled(busy)
                        if busy { ProgressView(value: progress) }
                    }
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                    if let image, let result {
                        Image(uiImage: image).resizable().scaledToFit()
                        Text("\(result.width) × \(result.height) 像素").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("保存长图") { saveResult(result) }.buttonStyle(.borderedProminent)
                            ShareLink(item: result.file).buttonStyle(.bordered)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("快捷指令入口").font(.headline)
                        Text("快捷指令使用“打开 URL：scrollshot://record”打开这个录屏页面。苹果的系统录屏确认仍需你点一次。").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(22)
            }.navigationTitle("录屏转长图").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPicker) { VideoPicker(selected: selectedVideo) }
                .onOpenURL { url in
                    if url.scheme == "scrollshot" && url.host == "record" {
                        status = authorized ? "请点上面的系统录屏按钮，再确认开始广播。" : "请先允许保存照片。"
                    }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { authorized = PhotoSaver.isAuthorized }
                }
        }
    }

    private func requestPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { value in
            DispatchQueue.main.async {
                authorized = value == .authorized
                status = authorized ? "已允许保存照片，可以开始长图录屏。" : "未获得保存权限。请在系统设置中允许此 App 添加照片。"
            }
        }
    }

    private func selectedVideo(_ selection: Result<URL, Error>) {
        switch selection {
        case .failure(let error): status = error.localizedDescription
        case .success(let url):
            busy = true; progress = 0; status = "正在本地处理录屏…"
            let cropTop = top / 100, cropBottom = bottom / 100
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let output = try VideoProcessor.convert(url, top: cropTop, bottom: cropBottom) { value in
                        DispatchQueue.main.async { progress = value }
                    }
                    let preview = UIImage(contentsOfFile: output.file.path)
                    DispatchQueue.main.async {
                        if let previous = result { try? FileManager.default.removeItem(at: previous.file) }
                        result = output; image = preview; busy = false
                        status = output.partialReason ?? "长图已生成，请检查接缝后保存。"
                    }
                } catch { DispatchQueue.main.async { busy = false; status = error.localizedDescription } }
            }
        }
    }

    private func saveResult(_ output: StitchResult) {
        PhotoSaver.save(output.file) { value in
            DispatchQueue.main.async {
                switch value {
                case .success: status = "长图已保存到照片。"
                case .failure(let error): status = error.localizedDescription
                }
            }
        }
    }
}
