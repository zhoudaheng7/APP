# 0.4.0 开源审查与集成范围

2026-10-16；只审查公开源码，没有连接用户手机或改系统文件。

## 混音

HaishinKit.swift，BSD-3-Clause，上游固定提交 `56084ed0d5edcba46e3732ee2ed57161a97f3173`。
来源：https://github.com/HaishinKit/HaishinKit.swift/blob/56084ed0d5edcba46e3732ee2ed57161a97f3173/HaishinKit/Sources/Mixer/AudioMixerTrack.swift

AudioMixWriter 适配其每路独立 AVAudioConverter、单声道映射双声道及 PCM 归一化方法；重写有界时间戳对齐与单文件输出，没有引入网络推流、摄像头或整套 SDK。完整 BSD 通知附于 App/Resources/HaishinKit-LICENSE.txt，并随 IPA 分发。两路各0.5增益保留峰值余量；不提供回声消除，扬声器外放时麦克风可能再次收录播放声，推荐耳机。

## 通话项目：研究结果，不作为已集成功能

- AirBeep：GPL-3.0，审查提交 `08217274a2d2f0f1db9246b9b8c4b89760d15439`。https://github.com/LinkPass888/AirBeep 。CallRecordingToneService 只修改系统录音提示音，依赖 airlift、配对文件及 LocalDevVPN 环境；没有通话音频采集或开始/停止接口。版本门槛不证明此机可用。refresh 读取缓存而非系统实测；没有备份时 restore 路径也不能据此证明恢复。未复制其代码/二进制/静音资源，未更改系统文件。
- AirliftSilence：MIT，审查提交 `552384025ec9782c472a8dcf152e965452567424`。https://github.com/YiHoooong/AirliftSilence 。Windows USB 配对环境的提示音文件处理，同样不是独立录音引擎；作者的27.0.1测试不能代证本机。
- TrollRecorder：开源 CLI 为 AGPL-3.0，审查提交 `4e8b65aacbc77d32540b5b4c06ce4ebbc4777e68`。https://github.com/Lessica/TrollRecorder 。实际双向采集使用私有 AudioQueue tap、CanTapTelephony、SystemWideTap 等权限，README 限制 TrollStore/越狱与15–17；普通企业签名iOS27不可直接复用，完整GUI也非全部开源。未复制代码或加伪造权限。

当前没有可交付的“快捷指令直接开始系统/微信/WhatsApp双向通话录音”后端。菜单通话项明确显示方案说明，不启动假计时或将麦克风外录冒充通话内录。系统电话录音由系统管理，声屿灵动岛不能停止它。

## 苹果公开接口

AppIntents / AppShortcutsProvider 提供录音菜单与两种模式动作，动作打开App并呈现系统采集确认；不跳过确认。LiveActivityIntent 提供 App 进程内的停止操作，用 sessionID 校验防止旧按钮停止新录音；系统杀进程后旧活动会清除并提示检查文件，不声称已保存。

录音采用主App的 ScreenCaptureKit 与可选 AVAudioEngine 麦克风，两个时间源都按系统host clock对齐；主App的 ScreenCaptureKit.captureMicrophone 官方平台列表未列iOS，不能直接搬macOS设置。广播使用ReplayKit两路音频；需系统麦克风开关实际打开。仅内部音不注册麦克风tap，广播即使收到audioMic也忽略。

ActivityKit 无法保证 App 未启动时独立广播扩展创建活动，因此控制中心独立开录仍通过系统录屏停止。没有灵动岛的设备可用锁屏实时活动；用户关闭实时活动时通过App/系统停止。长按灵动岛后点停止按钮；轻点紧凑岛通常是打开App。

参考：
- https://developer.apple.com/documentation/appintents/liveactivityintent
- https://developer.apple.com/documentation/appintents/audiorecordingintent
- https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturemicrophone
- https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:)
