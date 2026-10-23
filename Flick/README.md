# 一甩 0.2.0 · 原生 Liquid Glass 双机测试版

支持上下左右四向甩送照片、视频与普通文件。接收端先从边缘展开预览，随后接收原文件，只有文件长度和 SHA-256 完全匹配才确认送达。每次一个文件，上限 2 GiB。音效留给下一版。

App 内使用系统 PhotosPicker，设置 `.current`，不主动转码；选中即全屏甩送，不加入主页。也可在系统照片/文件中使用「分享 → 一甩」原生分享扩展，直接在分享窗口甩送。普通文件在工具栏选择。视频原文件收到后可播放、存入照片；文件可 Quick Look 预览、存储到文件和系统分享。预览缩略图会压缩，传输文件不压缩、不重新编码。原文件指系统选择器或分享来源交给本 App 的文件，无法替来源保证其导出前未转换；Live Photo 的照片及伴随视频尚不作为整套资源发送。

通过 Multipeer Connectivity 的加密会话传输，无需路由器或互联网，Wi-Fi 和蓝牙开关需要开启；实际无线链路由系统选择。双方允许本地网络并保持传输界面前台。没有实现关闭 Wi-Fi 后的纯 BLE 大文件通道。

Nearby Interaction 在运行时支持、获准且测到方向时显示真实方位和距离。当前手机竖屏，方向来自设备本地坐标；UWB 有视场和遮挡限制，无法保证任意摆放均能测量。数据超过 3 秒即清除。方向不可用时明确提示，四向手势仍发送给当前唯一的连接设备，入场使用发送方向的反向边缘。多设备空间路由未实现。

首次连接核对连接码并确认。P256 密钥保存在各入口的 Keychain，记住设备公钥；自动重连还需要对方签署本次随机挑战。开关和忘记配对可在连接页管理。分享扩展与主 App 各自保存配对状态，无强制 App Groups 签名能力；首次从分享扩展连接需要再确认一次。退出或被系统终止扩展会中断传输，请保持分享窗口打开直到已送达。扩展内的方位测量取决于系统是否提供，不能作为必需条件。

「快捷指令」可添加一甩「开始接收」，也支持 `flick://receive` 打开接收页。它们会拉起 App 并寻找已配对设备；不能绕过锁屏、强制把后台接收界面弹到前台。分享扩展不尝试通过非公开方式跳转主 App。

## 原生界面与构建

SwiftUI 系统导航、标签栏、PhotosPicker、`.glass` / `.glassProminent` 和 `GlassEffectContainer`，最低 iOS 26；新系统使用其原生 Liquid Glass。支持动态字体、减弱动态效果和按钮发送。没有网页套壳。

```sh
brew install xcodegen
swift test
xcodegen generate
xcodebuild build -project Flick.xcodeproj -scheme Flick -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
python3 scripts/package_ipa.py build/device/Build/Products/Release-iphoneos/Flick.app output/Flick-0.2.0-unsigned.ipa
```

IPA 包含真实 arm64 iPhoneOS 主程序和嵌入式 Share.appex。用手机已有证书重签时必须保留并同时签名扩展；删除扩展将失去系统分享入口。不需要上传个人私钥。若签名工具更改主 Bundle ID，扩展 Bundle ID 必须同步保持其前缀关系。

## 双机验收

1. 两台手机安装相同 v0.2，打开 App、允许本地网络。核对码并连接，在连接页允许超宽带权限。
2. 四方向分别甩送同一张照片，检查短拖回弹、对应边缘进入、预览与原文件状态分开、SHA-256 成功确认。
3. 测试 HEIC/JPEG、MOV/MP4、大视频与 PDF/ZIP；保存后比较文件大小和 SHA-256。Live Photo 资源包暂不在范围内。
4. 在系统照片/文件分享菜单启用一甩，打开自定义甩送界面；首次从此入口重新确认配对。接收方保持主 App 在前台。
5. 双方断开路由器/蜂窝网络而保留 Wi-Fi 与蓝牙开启，验证直连；测量手机不同朝向，确认失去方向时不显示旧方位。
6. 测试暂停接收、主动断开、掉线、前后台切换、自动重连开关与忘记配对。「开始接收」快捷指令应打开接收页。

规则单测和设备 SDK 编译不等于真机通过；仍需在用户的 iPhone 17 Pro Max / 16 Pro Max、iOS 27.0.1 上验证传输、UWB、分享扩展权限和签名工具兼容性。
