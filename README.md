# 录屏转长图 · iPhone 原生原型

目标：快捷指令打开原生录屏入口，用户在苹果系统界面确认录屏、回到聊天或页面缓慢向下滚动；停止后，录屏扩展在手机上去重、拼接并尝试保存长图到照片。视频和画面不上传服务器，不调用大模型，不需要 Picsew 会员。

## 当前验证状态

本项目是未编译的原生原型，不能把这个源码包当作安装包。已完成项目 YAML 和工作流配置检查、Python 打包脚本语法检查，验证打包器会拒绝未编译的输入。尚未执行 Xcode 编译、Swift 单元测试或 iPhone 实机测试。尚未生成 IPA，也未完成 IPA 签名。不要声称已验证完整功能。

特别需要实机验证：

- 免费签名是否完整保留并允许运行 ReplayKit 上传扩展。
- 主 App 获得的添加照片授权是否可用于录屏扩展。
- 停止广播后，扩展是否有足够时间完成长图编码及 PhotoKit 保存。
- 手机上的画面旋转、像素行方向、内存、匹配接缝和通知行为。
- iOS 27 上旧版本 ReplayKit API 的实际兼容性。

使用公开的 ReplayKit 系统选择器；不跳过苹果的录屏确认，不使用私有 API 自动点击系统按钮。录屏扩展名称是「长图录屏」。这里的“广播”是苹果的 API 名称，本程序不会把画面发到网络。

## 目录

- `ScrollShot/`：SwiftUI 主 App、系统录屏选择器、已有视频导入与本地处理。
- `Broadcast/`：ReplayKit 上传扩展；约每秒五帧处理，结束时尝试保存 PNG。
- `Shared/`：垂直位移匹配、细化接缝、按新增区域存储片段、生成 PNG、PhotoKit 保存。
- `Tests/`：已知位移、噪声、无关内容、像素方向、回滚去重及长度上限的 XCTest。
- `project.yml`：XcodeGen 工程定义，无 App Groups 或其他付费开发者特有服务依赖。
- `.github/workflows/build-ios.yml`：GitHub Actions 云端 Mac 编译、模拟器单元测试、生成未签名设备 IPA。

## 没有本地 Mac 时的编译路线

1. 创建你自己的 GitHub 仓库，建议名 `scrollshot-ios`、Private，勾选添加 README 初始化 main 分支。
2. 把本目录内容上传到仓库根目录，必须包括 `.github/workflows/build-ios.yml`。
3. 进入 Actions，等待 `Build iPhone IPA` 运行完成，或手动 Run workflow。
4. 只有测试和设备编译成功，`ScrollShot-iPhone` artifact 中才会包含真实的 `ScrollShot-unsigned.ipa`。
5. 若失败，先阅读日志并修复。不要用改后缀、源文件 ZIP 或模拟器产物代替设备 IPA。

GitHub 私有仓库的 macOS runner 使用量受账户套餐额度和计费设置限制；不要假设全部免费。工作流没有加入签名证书或 Apple ID，也不把凭据写入文件。

## Windows 签名安装

可使用 Sideloadly 对真实 IPA 做个人签名并安装；Apple ID 由用户自己在本地工具中输入。免费个人签名一般 7 天到期，仍需实际验证录屏扩展的权限与安装情况。签名时必须保留 `Broadcast.appex`，如果工具移除了扩展，App 会明确显示“录屏扩展未安装”。主 App 会读取安装后扩展的实际 bundle ID，以适配重签时的标识符改写。

此处尚无签名证书或配置描述文件，不能声称已签名。`.shortcut` 签名和 IPA 签名是不同流程。

## 安装后测试

1. 打开「录屏转长图」，点允许保存到照片；可选允许完成通知。
2. 点 App 中的系统录屏按钮，在系统弹窗中确认开始广播。
3. 切回目标聊天或页面，从内容顶部缓慢向下滚动。
4. 点系统红色录屏按钮结束，检查照片中是否保存了完整长图、是否有缺行或重复接缝。
5. 若扩展自动保存失败，用 App 的“转换已有录屏”功能单独验证拼接与相册保存，定位问题；这个备选入口不代表自动录屏流程已完成。

自动录屏版本默认裁掉顶部 12%、底部 14%；没有 App Groups，因此主 App 的导入视频裁剪设置不会同步到扩展。录屏输出宽度 480 像素、总量上限 180 万像素；导入视频输出宽度 720 像素、上限 360 万像素。超过上限会生成已确认的部分长图，并在通知或 App 中说明原因。

录屏初始切换 App 时，直到第一次识别到有效向下滚动前，首屏会随全屏变化重置；滚动开始后出现不可靠匹配会停止拼接，以避免默默错拼。初版要求从顶部向下；允许回滚到已录过的区域，但不支持向起始位置之前滚动。

## 快捷指令

安装 App 后，用 `URL: scrollshot://record` → `打开 URL`，可以放到控制中心或绑定轻点背面。它会打开录屏页面，系统选择器与开始录屏确认仍需用户操作。提供完整自动化承诺前，必须完成上面的实机验证。

## 本地 Mac 可选构建

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -project ScrollShot.xcodeproj -scheme ScrollShot -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ScrollShot.xcodeproj -scheme ScrollShot -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
python3 scripts/package_ipa.py build/device/Build/Products/Release-iphoneos/ScrollShot.app output/ScrollShot-unsigned.ipa
```

模拟器名称需替换为机器上实际可用的设备。测试代码没有在当前 Linux 环境执行。
