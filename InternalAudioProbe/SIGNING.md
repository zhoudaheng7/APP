# 企业签名要求 · 声屿

0.4.3包含广播与实时活动两个扩展。请签名服务同时处理主 App、`PlugIns/InternalAudioBroadcast.appex` 和 `PlugIns/RecordingActivity.appex`，保留两者，不能只签主可执行文件。

主 Bundle ID：`com.lightsquare.internalaudioprobe`。
扩展 Bundle ID：`com.lightsquare.internalaudioprobe.broadcast`。
实时活动扩展 Bundle ID：`com.lightsquare.internalaudioprobe.activity`，需同团队有效profile；该扩展不读取录音共享容器，不额外要求App Group或推送权限。
主App和广播扩展均需同一开发团队、有效 provisioning profile，并授权同一个 App Group：`group.com.lightsquare.internalaudioprobe`。

两个签名的 entitlements 都应包含：

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.lightsquare.internalaudioprobe</string></array>
```

源码中的 `App/AudioCapture.entitlements` 与 `Broadcast/AudioCapture.entitlements` 是构建要求模板，里面的 `$(AUDIO_APP_GROUP)` 在签名前应替换为实际获准的 Group ID；它们不是证书，也不是已生效权限。

如果签名服务改 Bundle ID，扩展 ID 必须位于新主 ID 下。若 App Group 也改名，需要同步改主 App 和扩展的 `Info.plist → AudioAppGroupIdentifier` 及双方签名 entitlements，并确保双方 provisioning profile 都授权该 Group。

不要添加不存在的 `com.apple.developer.replaykit.broadcast` entitlement。本版本只使用标准 Broadcast Upload Extension 注册和 App Groups。

App 的 `screen-capture` 和 `audio` 后台模式、NSSupportsLiveActivities、麦克风用途声明、图标资产、最低 iOS 27 和用户已有数据需要保留。麦克风默认关闭，混音才请求权限。建议覆盖安装，先导出旧音频；卸载再装可能清除录音。

安装后长按控制中心录屏按钮，选择「声屿 · 仅音频」→ 开始广播。结束后打开主 App，查看并只导出 M4A。

若签名服务不支持 App Groups，主 App 的 ScreenCaptureKit 内录仍可走本地 Documents；控制中心扩展会报告共享容器未配置，不会悄悄生成主 App 无法访问的录音。

首次签名后的扩展显示、App Group 访问、停止后分段完成都需要 iPhone 真机验证，云端构建成功不代证权限已配置。

签后可在 Windows/macOS 运行只读一致性检查：

```sh
python scripts/verify_signed_ipa.py signed.ipa --output signing-result.json
```

该工具检查三个目标的实际签名权限、描述文件授权/有效期、共享组与 Info 配置、版本和后台模式，只输出脱敏结果，不修改 IPA。它不验证密码学签名真实性或真机能力；macOS 的 Apple 签名验证和手机检查仍须分别完成。只改 Info 中的共享组或附带 entitlements 模板不能补齐签名权限。
