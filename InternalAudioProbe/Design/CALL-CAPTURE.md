# iOS 27.0.1 通话采集研究与独立实验

2026-10-17 Pacific。用户要求继续寻找普通企业签名可安装、覆盖系统电话与微信等通话的方案，并授权自行开发。用户没有提供已成功项目链接。机型和完整系统构建号尚未知。

## 当前结论与实验边界

尚未找到同时满足上述条件、已证明双方声音可取得的开源后端。声屿0.4.0已交付的普通内录、可选麦克风、快捷入口与实时活动不因此改写。新增独立 CallAudioProbe 应用标识 `com.lightsquare.callaudioprobe`，桌面名“声屿通话实验”，可与声屿并存，无App Group、扩展、配对文件或私有权限依赖。它是采集能力实验，不能标成通话录音已实现。

实验采用Apple公开SCK iOS27 API：系统picker全屏+用户选择麦克风；内部音与麦克风分别保存M4A、分别统计、分别试听。视频回调丢弃；不用AVAudioEngine。按官方示例尝试audio session激活，失败与interruption只记事件，继续尝试SCK，由SCK实际错误决定停止。内部音非零可能是其他App或提示音，仍须试听确认对方语音；本方/麦克风有声、文件大小、采样计数、系统已开始都不算双方成功。

实验不加入快捷指令或自定义灵动岛。先用App和系统采集标记停止；只有确认采集能力后才有集成快捷入口的依据。原声屿已有入口不受影响。实验开始前停止试听，采集中禁止试听以免音频会话和播放声干扰测量。

每次实验保存在专用 `Documents/CallAudioProbe/<UUID>/`。音频writer的session.json、probe.json及其他附属文件仅在该目录；分享仅提供已完成M4A。删除前确认，删除整个实验UUID目录，活动录制禁止删除；成功无额外“删除X条”提示。没有代用户删除任何真实数据或修改系统提示音。

## 官方接口证据

- [Apple DTS 2026年6月答复](https://developer.apple.com/forums/thread/835552)：CallKit协调音频会话，承载通话的App拥有该通话音频，没有旁路截取原生电话的框架。
- [企业应用仍适用沙箱和entitlement](https://support.apple.com/en-ca/guide/security/sec15bfe098e/web)、[TN3125签名与profile](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)：分发方式不会自行获得系统通话采集权限。
- [iOS27 SCK官方示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)及其[源码下载](https://docs-assets.developer.apple.com/published/91f0562d72a9/CapturingScreenContentInIOS.zip)：独立`.audio`、`.microphone`输出；filter.isMicrophoneEnabled代表用户选择。示例audio session激活失败后继续SCK，不能把旧AVEngine的中断直接当成SCK麦克风必定不可用。
- [AVAudioSession.setActive](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:))：其他App正在通话时，普通录音audio session可能因优先级失败。
- [开发者SCK真机报告](https://developer.apple.com/forums/thread/848245)：作者报告iOS27.0/iPhone15ProMax的普通音乐内部音正常，Zoom/Teams远端约70秒全部零，SCK麦克风可录本方。页面“3w”相对时间、3回复均作者，无Apple Staff确认。不能外推用户27.0.1/微信/WhatsApp的实测结果。
- [向通话加入合成声音](https://developer.apple.com/documentation/avfaudio/adding-synthesized-speech-to-calls)是发送声音的接口；[默认拨号App](https://developer.apple.com/documentation/livecommunicationkit/preparing-your-app-to-be-the-default-dialer-app)提供发起呼叫等能力；都没有已确认的其他通话App下行PCM读取接口。

## 公开源码核对（固定版本）

| 候选 | 固定提交 | 核对到的实际范围 |
| --- | --- | --- |
| [CallCapture](https://github.com/AdnanZulfiqar21/Iphone_Call_Recording) | a3b2a4336d01d011179220532d5adf38d3847e16 | ScreenCaptureKitEngine确实接收两路，但源码标远端UNTESTED，PROGRESS真机P14未开始，尚无企业签名双方成功证据；未核得复用许可证，未复制代码。 |
| [TrollRecorder](https://github.com/Lessica/TrollRecorder) | 4e8b65aacbc77d32540b5b4c06ce4ebbc4777e68 | 真AudioQueue私有tap；cli/call-recorder.plist需CanTapTelephony/SystemWideTap等系统权限。CLI LICENSE为AGPL-3.0。README旧范围15–17，作者另确认palera1n18.3；issue143明确暂不支持26，不能外推27或普通企业签名。 |
| [Bismath21/call-recorder-ios](https://github.com/Bismath21/call-recorder-ios) | 32830b3e44692e6f288ab8e3e3206d8cec13d79b | CallRecorderService为CXCallObserver+AVAudioRecorder，README承认环境声/免提，不是电话下行；未找到LICENSE。 |
| [qq709485488/CallRecorder](https://github.com/qq709485488/CallRecorder) | 3153cd7bef89a19d0b0dc64fe1dac2e363590425 | TRAudioRecorder仍普通录音；output tap只算幅度，没有把该buffer写入录音；无27双方证据，未找到LICENSE。 |
| [JonathanHuangg/Call-Recorder](https://github.com/JonathanHuangg/Call-Recorder) | 1057ed09aa0b4c3560834ef012591a2aa7dc04ec | ContentView按钮只print，没有通话采集，未找到LICENSE。 |
| [manmanking/CallRecord](https://github.com/manmanking/CallRecord) | 9b18861a360dd58ddbeb144852178b6656caf9d0 | 2017普通AVAudioRecorder，没有电话下行音源，未找到LICENSE。 |
| [ios-calltone-silence](https://github.com/jiutinglifeng/ios-calltone-silence) | a0f4d338eab4ffcb7444f272c07a6fa558183fb2 | MIT桌面USB工具；作者27.0.1/24A446验证的仅系统提示音处理，不是IPA或采集器。 |
| [AirBeep](https://github.com/LinkPass888/AirBeep) | 08217274a2d2f0f1db9246b9b8c4b89760d15439 | GPL-3.0，修改系统提示音，需非公开配对/VPN环境；无双向音频后端，详见OPEN-SOURCE.md。 |
| [AirliftSilence](https://github.com/YiHoooong/AirliftSilence) | 552384025ec9782c472a8dcf152e965452567424 | MIT，Windows/USB提示音处理；27.0.1作者测试不能代证通话捕获。 |

LingyeHan/HLYCallRecorder查询无可读commit（API409）；Android、Windows WeChat recorder、macOS tap都不作为iPhone企业IPA成功证据。没有运行这些仓库、使用它们的二进制、修改设备或引入未许可代码。

## 真机实验顺序与通过标准

1. 企业签名独立CallAudioProbe IPA，iOS27.0.1安装并保留原声屿。记录关于本机的机型/完整版本，不记录电话号码或账号。
2. 普通音乐对照：戴耳机播放普通视频/音乐，开系统全屏采集和麦克风；本人说短句，停止后分别试听内部轨和麦克风轨。确认两来源独立、可解码、系统停止实际结束采集。
3. Phone、微信分别先采集后通话、先接通后采集；再测其他实际使用的通话App。每次10–30秒，双方轮流说不同短句，戴耳机排除免提串音。通话来源和顺序由用户自行标记；不自动读取联系人或通话历史。
4. 内部轨能辨认对方说的话才记录该App/路由测试通过；麦克风轨用于核对本方。全零、无buffer、permission错误、只有本方、缺一方均保留真实失败结果，不升格为全部通话支持。
5. 核对无视频轨、仅M4A分享、总大小；删除一次测试目录后其音频/诊断均消失，其他记录仍在。普通声屿与本实验各自的数据互不读取。

云端只能验证编译、合成PCM统计、真实编码/轨道和包结构。签名、系统采集许可、通话音轨策略、耳机/蓝牙、后台及真机双方声音仍待实际iOS27.0.1验收。若SCK不给对方采样，后端编码/混音/快捷指令无法补出该声音。可自研的SIP/PJSIP录音需要通话由自有客户端/服务器承载，不能替代现有微信通话；外置物理采集则改变硬件前提，均不是用户当前全部条件的已实现结果。
