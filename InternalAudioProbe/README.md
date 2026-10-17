# 内录验证 · iPhone iOS 27

验证目标：在用户主动通过苹果系统选择器授权后，采集其他 App 可提供的内部音频，直接写为 AAC/M4A；不保存视频、截图或麦克风音频。无账号、网络上传、转写模型或第三方运行时依赖。

这是验证版本。源码存在、云端编译成功、安装成功、文件有音轨和真实可听声音是不同阶段。部分课程、受保护内容、通话、锁屏与音频路由可能无法捕获，必须分别验收。

## 结构

- `App/`：SwiftUI 界面、ScreenCaptureKit 系统选择器与生命周期。
- `Sources/AudioCore/`：PCM 电平检查、AAC/M4A 编码、每分钟分段、元数据日志。
- `Tests/AudioCoreTests/`：真实合成 PCM 经 AAC 编码后检查音轨/零视频轨；静音、重复时间戳及无音频场景。
- `project.yml`：XcodeGen 工程，最低 iOS 27，无 Broadcast 扩展或 App Groups。
- `ci/internal-audio-probe.yml`：独立 GitHub Actions 工作流模板。
- `scripts/package_ipa.py`：只接受实际 arm64 iPhoneOS Mach-O 设备应用，打包为未签名 IPA 并生成 SHA256 校验记录。

## 原型行为

系统仍可能显示屏幕采集提示；应用接收的画面帧直接丢弃，不复制、不编码、不写磁盘。只注册内部 `.audio` 和画面丢弃回调，不注册 `.microphone`，没有麦克风权限声明。

音频直接编码为 96kbps AAC/M4A，每分钟一段。Documents/Recordings 下只持久化 `.m4a`、`session.json` 与 `inspection.json`。停止后逐文件检查音轨和视频轨；无音频或持续静音会明确报告失败。异常终止时先前完成段保留，正在写的最后一段可能损坏。未正常结束的历史记录会标记，不能算完整录音。

## 企业签名安装

1. 将真实构建产物 `InternalAudioProbe-unsigned.ipa` 交给你们的企业签名工具。
2. 由签名服务正确生成签名和 provisioning profile 后安装；不需要给本工程提供证书私钥。
3. 工具须保留 `UIBackgroundModes: screen-capture` 和 iOS 27 最低系统要求。
4. 打开「内录验证」，点「开始内录」，在苹果系统界面允许采集。
5. 切到播放来源 App，播放 30 秒以上；回到本 App 停止。
6. 点「检查音轨」，应显示音轨大于 0、视频轨为 0；逐段试听，确认内容确实来自播放来源。
7. 点导出保存音频和 JSON。也可通过 Finder/文件共享访问 Documents。

签名不能增加系统录音权限；安装与后台采集兼容性仍需真机验证。此版本不支持 iOS 26 及更早系统。

## 验收顺序

先测试公开普通视频或网页播放，再测试实际课程。分别记录：扬声器、有线/蓝牙耳机、切换 App、5 分钟跨段、30 分钟长录、系统停止按钮、锁屏。确认不是麦克风外录：佩戴耳机并在旁讲话，结果应包含播放内容而不包含旁边人声。无法录制时导出 JSON 诊断，不凭“录制中”字样判断成功。

## 编译

使用安装 Xcode 27 / iPhoneOS 27 SDK 的 Mac；GitHub 官方 `xcode-27` arm64 runner 当前列有此工具链。将工程放在获准仓库的 `InternalAudioProbe/`，工作流放在 `.github/workflows/internal-audio-probe.yml`；触发分支见工作流。不会覆盖仓库中其他应用。

```sh
swift test
brew install xcodegen
xcodegen generate
xcodebuild build -project InternalAudioProbe.xcodeproj -scheme InternalAudioProbe -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
python3 scripts/package_ipa.py build/device/Build/Products/Release-iphoneos/InternalAudioProbe.app dist/InternalAudioProbe-unsigned.ipa
```

CI 不含任何 Apple ID、签名证书或录音数据。私有仓库额度取决于账户，未经用户明确同意不购买资源或开启计费。

## 参考与实现范围

本工程自行实现音频写入和界面，未引入或复制第三方 SDK。参考 Apple ScreenCaptureKit 文档与官方 iOS 示例、LiveKit 的 iOS ScreenCaptureKit 生命周期实现及 HaishinKit 的音频/画面分流设计。

- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio
- https://github.com/livekit/client-sdk-swift/blob/main/Docs/ios-screen-sharing.md
- https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/

当前构建与真机状态见本地 STATE.md；仅在实际远程构建回执成功后才交付 IPA。
