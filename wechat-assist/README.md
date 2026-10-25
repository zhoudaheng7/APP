# 知会 · 微信 AI 助手 0.1

个人自用首版：Windows 对你选定聊天的可见文字做本地 OCR，iPhone 通过配对读取上下文、提问并生成候选话术；手动编辑后复制，在微信确认对象并发送。

## 当前交付状态

- 已提供：Windows 服务、区域选择与 OCR 采集源码、电脑工作台、iPhone SwiftUI 工程、待自签真机 IPA、离线交互预览、自动检查与 macOS 编译工作流。
- 已验证：本机微信版本 4.1.15.56 的可访问性接口没有返回消息正文；本地 Windows OCR 能识别合成中文聊天图片；20 项自动检查通过（含 17 项后端检查及 3 项 IPA 格式校验检查）；Edge 下 1440/1024/850/390/320 宽度无横向溢出；本机 HTTP 工作台到模拟模型、HTTPS 手机接口联通检查通过；GitHub 云端 iPhoneOS 编译成功，IPA 的 arm64 架构、0.1.0 版本、iOS 17.0 最低版本和文件哈希已复核。
- 尚未验证：真实微信持续截取和切换聊天保护的端到端运行、真实模型服务、iPhone 真机局域网通信、用户签名和安装。**此交付包含待自签 IPA，需要你使用自己的工具签名后安装。**
- 离线预览中的人物、聊天和生成回复全部为虚构示例。预览不连接微信，不调用 AI。

## 能力与使用条件

1. iPhone 普通 App 无法独立后台读取个人微信数据库。此方案依赖 Windows 开机、微信登录。
2. 首版只处理一个已选聊天的可见区域。不是全量历史导出，不自动遍历会话，不转写语音，不解析图片。
3. Windows 微信需在前台、保持选择区域时的位置和大小。失去前台或切换聊天后暂停读取；窗口移动后需要重新框选。读取周期为 OCR 处理时间加 2 秒，不保证每条消息都被捕获。
4. iPhone 与 Windows 在同一局域网。iPhone App 打开时轮询同步，后台、锁屏、电脑休眠或断网时不保证持续同步；首版不含外网中继和 APNs 推送。
5. 编辑回复时，可以手动分析最近 120 秒内的最后一次上下文；界面提示暂停状态。最新识别内容变化后，旧草稿会保留并显示过期提示，需重新核对。
6. 自动生成需要在 Windows 配置模型并主动开启，最短 12 秒请求一次。不确定说话人时不会推断消息归属。
7. 不包含微信发送接口；复制到剪贴板后由用户回微信发送。

微信对未经授权的第三方读取、控制与自动化操作存在使用限制，屏幕辅助识别也不能承诺获得官方认可或无账号风险。参见[微信软件许可及服务协议第 8.2 条](https://oper.my-qcloud.com/cgi-bin/readtemplate?lang=zh_CN&s=default&t=weixin_agreement)。

## Windows 运行

需要 Windows 10/11、带中文识别能力的 Windows OCR、Python 3.11+。解压到普通用户目录即可；不需要修改微信文件或管理员权限。

推荐直接双击 `Start-Windows.cmd`，会启用 iPhone 配对接口并打开工作台。也可以在本目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Windows.ps1
```

连接 iPhone 时运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Windows.ps1 -Phone
```

脚本优先使用目录中的虚拟环境、PATH 中的 Python 或本机已安装的 Codex Python 运行时；缺少依赖时会在本目录建立 `.venv` 并安装 `cryptography`。若未找到有效 Python，先安装 Python 3.11+ 并加入 PATH。上述参数只对本次进程生效，不修改全局执行策略。

工作台仅绑定 `127.0.0.1:8765`。`-Phone` 额外开启局域网 HTTPS 8766 端口。工具不会修改防火墙；如果系统询问网络访问权限，由你按自己的网络条件决定。不要做公网端口映射。

### 读取指定聊天

1. 打开一个微信主窗口，进入需要辅助的聊天。确保标题和消息区域可见。
2. 在工作台点「选择聊天区域」。选择器会把微信带到前台。
3. 第一次只圈选顶部聊天名称的文字；第二次圈选消息区域，避开联系人列表、标题和输入框。Esc 可取消。标题识别结果作为本次会话标识；同名联系人不能靠标题可靠区分，应由你确认实际对象。
4. 在工作台点「开始读取」，再切回微信。工作台失去读取状态时会显示原因。要在电脑工作台操作 AI 时，采集会暂停，可手动使用最近上下文；返回微信后恢复。
5. 在工作台配置你自己的模型 API 基础地址、模型 ID 和密钥。适配的是 `POST {基础地址}/chat/completions`，并非所有模型服务都兼容。密钥只存在当前服务进程，不写入配置、不下发到 iPhone。
6. 点击生成，或主动开启「自动生成」。开启后选区识别文本会发送到你配置的模型服务。
7. 关闭运行窗口或按 Ctrl+C 停止。记录和草稿不落盘，关闭后清空。

## iPhone 编译、安装与配对

本机是 Windows，已通过 GitHub 云端 Mac 编译出 `WeChatAssist-0.1.0-unsigned.ipa`，最低支持 iOS 17.0。使用你已有的自签工具导入该 IPA、签名并安装。`ios/` 提供相应原生 SwiftUI 源码与 XcodeGen 配置；源码压缩包不能当作 IPA 安装。

在 Mac 上安装 Xcode 和 XcodeGen 后：

```sh
cd ios
xcodegen generate
open WeChatAssist.xcodeproj
```

在 Xcode 中设置自己的 Bundle ID 和签名 Team，连接 iPhone 后编译安装。iOS 最低版本 17.0。用于安装的 IPA 需要相应证书与描述文件；不需要在聊天里提供 Apple ID 密码、私钥或证书口令。详见 [Apple 真机分发说明](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。

工程还提供 `.github/workflows/ios-build.yml` 作为可选模拟器编译检查。本次真机 IPA 由 `wechat-assist-ipa.yml` 工作流生成，没有向云端提供任何 Apple 签名凭据。

### 没有 Mac，但已有自签工具

已准备 `.github/workflows/wechat-assist-ipa.yml`：使用 GitHub 云端 macOS 编译 **arm64 iPhoneOS 真机版本**，打包为 `WeChatAssist-unsigned.ipa`，不需要把 Apple 账号或签名证书交给云端编译。

它支持把工程独立放在仓库的 `wechat-assist/` 子目录，或将本工程作为独立仓库使用。指定的 `codex/wechat-assist*` 分支推送可触发编译；也支持在工作流可手动触发时运行。工作流输出包含待自签 IPA、格式检查报告和编译日志，保留 7 天。

已按你的授权上传到公开仓库 `zhoudaheng7/APP` 的 `codex/wechat-assist` 独立分支。云端构建 [40170001942](https://github.com/zhoudaheng7/APP/actions/runs/40170001942) 成功；IPA 对应提交 `7fb0a1b6d1bf3fdee50f03206093fcb1b6afb785`。签名与 iPhone 真机运行尚未验证。

编译完成后的包会交由你的现有自签工具签名安装。具体签名步骤取决于你使用的工具。签名成功仍需在真实 iPhone 验证启动、配对和网络访问。已有签名工具不会赋予 App 读取微信数据库或后台监听微信的权限。

`ios/scripts/validate_ipa.py` 会检查 `Payload/*.app`、iPhoneOS 平台标识、arm64 Mach-O 及其 iOS 平台加载指令，避免把模拟器包错当作真机包；格式检查不等于签名验证或真机运行验证。

配对步骤：

1. 用 `-Phone` 启动 Windows 服务，电脑和 iPhone 接入同一局域网。
2. 工作台中打开「iPhone 配对」，复制整段配对 JSON 到自己的 iPhone。
3. 在原生 iPhone App 中点系统粘贴按钮，粘贴配对信息并连接。
4. App 会校验配对时的 SHA-256 证书指纹及证书有效性；不是接受任意证书。配对凭据存入设备 Keychain。
5. 服务重启或工作台中「使旧配对失效」后需要重新配对。若列出的第一地址来自虚拟网卡，选用与手机同网段的其他地址。
6. 手机的「回复助手」「上下文」「连接」三页分别用于话术编辑、核对原文和查看连接状态。

## 数据处理

- 只对明确选择的区域截图，截图在内存中交给本地 OCR，不写入图片文件；聊天文字与候选结果也保存在内存。
- `runtime/region.json` 仅记录选区、窗口和聊天标题；`runtime/bridge-key.pem` 是本机服务证书私钥。不要分享 `runtime/`，源码压缩包不含此目录。
- 手机 API 通过 HTTPS 和随机配对令牌鉴权，无法使用手机令牌配置模型或获得管理端配对信息。
- 请求日志不记录正文、令牌或模型密钥。只有你主动配置并请求 AI 时，上下文才会进入所选模型服务；自动生成开启后会持续按变化触发请求。

## 验证与后续验收

```powershell
python -m unittest discover -s tests -v
```

第一次真实运行仍需完成：同一聊天新文字出现后的采集、暂停与恢复、切换聊天时不串入其他聊天、窗口移动后的暂停、真实模型生成、iPhone 前台同步与断线恢复。不要把单元检查、合成 OCR 或离线演示等同于这些真机验收。

参考：[Apple 沙盒说明](https://support.apple.com/en-ca/guide/security/sec15bfe098e/web)、[Apple 局域网权限](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[Microsoft OCR 接口](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine.recognizeasync)。
