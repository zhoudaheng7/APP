# 一甩 · 原生 Liquid Glass 测试版

iPhone 双机直传照片：确认附近连接，向左右指定方向甩出；对方从对应边缘接住、自动展开。接收方可以暂停；原图通过 SHA-256 校验之后才确认送达。支持原图保存和系统分享。

使用 SwiftUI 的系统导航、标签栏、原生 PhotosPicker、`.glass` / `.glassProminent` 按钮和 `GlassEffectContainer`。最低 iOS 26，在 iOS 27 使用系统原生材质；遵循动态字体和减弱动态效果。没有兼容外观开关或网页套壳。

照片通过 Multipeer Connectivity 加密会话在已确认的设备之间发送，不经过云端照片服务。第一版建议同一 Wi-Fi、Wi-Fi 与蓝牙开启、双方 App 保持前台且并排竖屏。系统本地网络权限必须允许。

## 构建与签名

`brew install xcodegen` → `swift test` → `xcodegen generate` → 用 iOS 26 或更新 SDK 的 Xcode 执行：

```sh
xcodebuild build -project Flick.xcodeproj -scheme Flick -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
python3 scripts/package_ipa.py build/device/Build/Products/Release-iphoneos/Flick.app output/Flick-0.1.0-unsigned.ipa
```

产物是含真实 arm64 iPhoneOS 可执行文件的未签名 IPA。用户使用手机中已有的证书分别重签安装，不需要把私钥上传到此仓库。

## 双机测试

1. 两台手机分别重签安装同一 IPA，并打开「一甩」。
2. 点连接，允许本地网络。找到对方设备，核对连接码，由其中一台发起连接；另一台点允许连接。
3. 发送方设置对方在左侧还是右侧。选择系统照片库中的一张图片，按住照片向指定方向甩出，或点发送按钮。
4. 接收方检查入场边缘、自动放大、原图接收确认。可存入相册或系统分享。
5. 验证暂停接收、短拖回弹、反向拖动、断连重试和切到后台后的重连。动画完成不等于原图送达。

第一版不自动识别真实空间位置；左右关系由用户设置。支持普通静态照片原图，不包含 Live Photo 的伴随视频。当前没有两台实体 iPhone 的验收证据，不能把设备编译或规则测试描述为真机传输成功。
