# 内录验证 0.3.1 · iPhone iOS 27

## 0.3.1 首次播放进度修复

波形的 UIViewRepresentable 直接观察播放器状态，首次播放、暂停与继续播放时立即启停原生显示链，不需要先拖动波形来触发进度。UI回归检查在任何定位之前验证时钟和游标自动前进、暂停保持不动、继续播放重新前进，且定位提交数始终为0；随后继续验证原来的3次拖动/点击。帧更新仍留在UIKit，不逐帧刷新SwiftUI列表。

## 0.3.0 紧凑界面与拖动

首页合并录音/教程区域，开始按钮文字居中；午夜蓝底色配青绿点缀，与原图标统一。正常录音采用一行标题/日期/状态、紧凑音轨/时长/大小和一行检查/导出/删除，完整检查详情可点开。

按用户追加要求，进度条直接融入真实音轨波形，不再另占一行。竖向游标与已播放颜色显示位置，上方一行时长/“左右拖动音轨”/大小，整段波形任意位置可点击或起拖，松手才提交定位。录音卡片进一步收紧内边距与音轨高度。

原生 UIControl 触摸期间只预览位置，放手才提交一次定位；原先播放的音频会恢复。VoiceOver 离散调节也可定位。当前可见音轨的 CADisplayLink 更新 UILabel/游标/图层遮罩，不再将时间广播到整个 SwiftUI 列表。波形几何缓存，后台串行解码并缓存24条；列表文件信息在刷新时获取，不在逐帧渲染里扫描磁盘。后台、暂停及移出窗口时停止显示链。

主 App 开启 CADisableMinimumFrameDurationOnPhone，并按屏幕 maximumFramesPerSecond 设置 preferredFrameRateRange。系统仍根据电量/温度/用户设置决定实际刷新率，不声称真机恒定满帧。UIProbe 仅在 CI 专用启动参数下记录回调频率、定位提交数、波形构建数，不进入正常用户界面，不代表真机 FPS。

Apple 官方参考：
- https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone
- https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange

验证目标：在用户主动通过苹果系统选择器授权后，采集其他 App 可提供的内部音频，直接写为 AAC/M4A；不保存视频、截图或麦克风音频。无账号、网络上传、转写模型或第三方运行时依赖。0.2.0 增加新图标、仅音频导出和控制中心 Broadcast Upload Extension；新入口需要签名时保留扩展及 App Groups，尚待真机验证。

这是验证版本。源码存在、云端编译成功、安装成功、文件有音轨和真实可听声音是不同阶段。部分课程、受保护内容、通话、锁屏与音频路由可能无法捕获，必须分别验收。

## 结构

- `App/`：SwiftUI 界面、ScreenCaptureKit 系统选择器与生命周期。
- `Sources/AudioCore/`：PCM 电平检查、AAC/M4A 编码、持续录音、按需合并、元数据日志。
- `Tests/AudioCoreTests/`：真实合成 PCM 经 AAC 编码后检查音轨/零视频轨；静音、重复时间戳及无音频场景。
- `project.yml`：XcodeGen 工程，最低 iOS 27；主 App + 广播扩展，共享 App Group。
- `Broadcast/`：控制中心直接开录扩展，仅接收内部音，不写画面或麦克风。
- `Shared/`：共享容器定位；保留原 Documents 录音目录。
- `Design/`：imagegen 生成的图标源图和提示词，构建时由 sips 统一尺寸。
- `SIGNING.md`：企业重签所需扩展与 App Groups 配置。
- `ci/internal-audio-probe.yml`：独立 GitHub Actions 工作流模板。
- `scripts/package_ipa.py`：只接受实际 arm64 iPhoneOS Mach-O 设备应用，打包为未签名 IPA 并生成 SHA256 校验记录。

## 原型行为

系统仍可能显示屏幕采集提示；应用接收的画面帧直接丢弃，不复制、不编码、不写磁盘。只注册内部 `.audio` 和画面丢弃回调，不注册 `.microphone`，没有麦克风权限声明。控制中心 ReplayKit 路径也明确忽略 `.audioMic`，即使系统麦克风开关被打开也不会写入。

音频直接编码为 96kbps AAC/M4A，持续保存为 recording.m4a，不按分钟切段；长度由可用存储、系统状态和来源播放决定。手动停止或系统中断后结束。音频格式改变时可能产生兼容分段，可通过合并功能输出一个文件。App 内录音仍保留在 Documents/Recordings；控制中心录音写入 App Group/Recordings。两者均只持久化 `.m4a` 和 JSON 诊断。分享按钮仅导出已完成的 M4A，JSON 留在本机，未完成文件不分享。停止后逐文件检查音轨和视频轨；无音频或持续静音会明确报告失败。持续录制不再按分钟轮换。正常停止后完成文件；若进程被强制终止，正在写的音频可能无法完成。旧版已完成的分段继续保留，不自动搬迁或删除。未正常结束的历史记录会标记，不能算完整录音。

## 录音记录与可见反馈

- 每条录音显示真实解码波形、当前/总时长、播放或暂停状态，拖动进度条可定位。
- 每条录音显示实际音频文件总大小，播放音轨旁显示该文件的大小，自动使用 KB/MB/GB；合并记录按新文件大小显示，不计 JSON 诊断。
- 检查音轨立即在当前卡片显示检查中，随后显示音轨/视频轨数量或错误。
- 点选择，可按开始时间顺序合并多条录音为一条新记录；原记录保留。旧版多段记录也可合并为一个文件。
- 单条或批量删除均需在 App 内明确确认；活跃的控制中心录音不能删除。删除仅限当前录音 UUID 子目录，不触及目录根、其他容器或已导出的文件。

## 企业签名安装

1. 将真实构建产物 `InternalAudioProbe-unsigned.ipa` 交给你们的企业签名工具。
2. 由签名服务正确生成签名和 provisioning profile 后安装；不需要给本工程提供证书私钥。
3. 工具须保留 `PlugIns/InternalAudioBroadcast.appex`、`UIBackgroundModes: screen-capture` 和 iOS 27 最低系统要求；主 App 与扩展需要同一有效 App Group 权限，具体见 SIGNING.md。
4. 可打开 App 点「开始内录」；或直接长按控制中心「录屏」→ 选择「内录 · 仅音频」→ 开始广播。后者不需要预先打开主 App，但需要共享容器权限正确。
5. 切到播放来源 App，播放 30 秒以上；App 内启动的录音回到 App 停止，控制中心启动的录音从系统录屏按钮停止。
6. 点「检查音轨」，应显示音轨大于 0、视频轨为 0；逐段试听，确认内容确实来自播放来源。
7. 点「导出音频」只保存 M4A。JSON 诊断保留在 App 内；原 Documents 音频也可通过文件共享访问。

签名不能增加系统录音权限；安装与后台采集兼容性仍需真机验证。此版本不支持 iOS 26 及更早系统。

## 验收顺序

先测试公开普通视频或网页播放，再测试实际课程。分别记录：扬声器、有线/蓝牙耳机、切换 App、5 分钟跨分钟持续录音、30 分钟长录、系统停止按钮、锁屏。确认不是麦克风外录：佩戴耳机并在旁讲话，结果应包含播放内容而不包含旁边人声。无法录制时可从文件共享取出 JSON 诊断，不凭“录制中”字样判断成功。

## 编译

使用安装 Xcode 27 / iPhoneOS 27 SDK 的 Mac；GitHub 官方 `xcode-27` arm64 runner 当前列有此工具链。将工程放在获准仓库的 `InternalAudioProbe/`，工作流放在 `.github/workflows/internal-audio-probe.yml`；触发分支见工作流。不会覆盖仓库中其他应用。

```sh
swift test
brew install xcodegen
bash scripts/prepare_icon.sh
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

当前构建与真机状态见本地 STATE.md；仅在实际远程构建回执成功后才交付 IPA。新增控制中心入口的签名、容器访问、扩展停止后最终分段完成需要单独验证；先前主 App 内录成功不代证扩展已完成。
