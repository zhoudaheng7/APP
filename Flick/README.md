# 一甩 0.4 开发版

原生 SwiftUI / Liquid Glass，最低 iOS 26。当前迭代只编译与测试，不自动生成 IPA。已交付的 0.3 IPA 不包含本轮变更。

## 本轮实现

- 附近列表来自 Core Bluetooth 扫描，移除 20 米判断；超宽带只提供可选的实际方位提示。
- 保留系统高速直连，新增可关闭 Wi-Fi 的独立 BLE GATT 通道。两种通道都传来源交给 App 的原始文件，不转码；预览图单独缩小。每个文件非空且不超过 2 GiB，一批最多 50 个。
- P256 签名核验已信任设备。首次确认后默认连续接收，可单独撤销信任、暂停接收或改回逐次确认。本地好友申请仍需要双方同意。
- BLE 使用每次连接新建的 Curve25519 密钥、绑定双方身份/随机数/临时密钥的 P256 签名、方向独立的 AES-GCM 密钥和严格序号。GATT 按实际 MTU 分片，遵守写入响应/通知背压；文件每 16 KiB 确认偏移，最终核对字节数与 SHA-256 后才回送送达确认。
- 主 App 任意前台页面都能接收，不再依赖接收页面出现来启动原文件。收到内容时保留正在编辑的发送选择，接收列表按 ID 保存每个项目。
- 主 App 声明蓝牙 central/peripheral 后台模式。提前建立并信任纯蓝牙连接后，可在系统允许的蓝牙事件执行期间接收；后台保存校验成功的文件，回到 App 查看。高速直连进入后台会暂停，不能自动无缝切换为 BLE。强制退出、系统终止或中断时不保证接收，也不能后台强制弹出全屏内容。
- 系统照片/文件多选 → 分享 → 一甩，直接进入批量甩送窗口。主 App 内选择照片、视频或文件后同样直接进入甩送窗口，不加入主页、不要求用户先手动导入。长按约 0.18 秒后四向拖甩，或使用发送按钮。
- 视频优先请求 movie 文件表示，保留当前编码；不再同步解码首帧，不因封面无法生成而拒绝原视频。复制及哈希在准备阶段提供进度和取消，视频播放器独立异步加载。批量缩略图限制内存占用。
- 按顺序逐项发送，已确认送达的项目保留完成状态。停止/失败后可重试未确认项目；接收端对已经校验保存的相同文件 ID 和哈希回送已有收据，避免确认丢失后重复入库。
- 已接收文件存入 Application Support 收件箱，不被 24 小时临时文件清理删除；可长按接收列表条目删除。

## 明确的适用范围

真实无线速度、两个 BLE 角色的后台行为、重签后权限、iPhone 17 Pro Max / 16 Pro Max 及 iOS 27.0.1 需要双机实测。编译成功与模拟器测试不能证明这些硬件场景通过。BLE 视频可能很慢，较大的前台视频可使用高速直连；没有声称始终后台在线或断点续传跨进程恢复。蓝牙状态恢复回调已加入，但连接加密状态不跨进程持久化，恢复后可能需要重连与重发当前文件。

分享扩展不强制要求 App Groups，便于现有手机签名证书重签；因此主 App 与扩展的配对身份、设置和好友独立。接收者第一次信任主 App 与第一次信任该手机的分享扩展，分别确认一次；同一入口随后可连续发送。若希望两个入口只确认一次，需要后续结合实际签名能力配置共享 Keychain/App Group 并验证。

Live Photo 的照片与伴随视频尚未作为一个资源集合传送。iCloud 原件未下载时，系统可能先下载，需要互联网；原件已在本机时，两种附近传输均无需互联网。Android/HarmonyOS 客户端、远程服务、云账号聊天和推送仍未接入。本轮没有把模拟版的远程/跨系统交互当作真实功能。

音效、静音、触感和 6 个可切换 App 图标延续 0.3 版。声音是原创测试合成音效/普通中文合成语音，遵循系统静音与音量；界面使用原生玻璃按钮、表单、导航和标签栏。

## 开发验证

macOS / Xcode 26+：

```sh
brew install xcodegen
swift test
xcodegen generate
xcodebuild build -project Flick.xcodeproj -scheme Flick -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Flick.xcodeproj -scheme Flick -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO
```

核心测试验证四向判断、认证、接收策略、帧边界、重放/篡改、文件偏移，以及 2 MiB 原文件经加密 GATT 分片后的字节一致。iOS 测试生成实际 H.264 MOV，验证视频准备不改变字节、封面不可用时仍准备原件、多选中 movie 优先于缩略图、单项失败保留其余项目、取消及收件箱文件名冲突。

工作流仅上传测试和编译日志，无打包步骤。用户再次明确要求生成 IPA 时，才运行打包脚本。两台需同时更新协议 4，不能与 0.3 / 协议 3 混用。
