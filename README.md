# Win Voice Hotkey

**把 Windows 语音输入放到顺手的一颗按键上。**

版本 **0.1.2**，面向 Windows 11 x64。默认鼠标后退侧键（XButton1）打开 Win+H，前进侧键（XButton2）真正关闭语音面板。可以更换键盘单键、鼠标键或滚轮，也可以用同一个键切换打开和关闭。

## 下载与开始

从 [v0.1.2 Release](https://github.com/SuTaiHui1/win-voice-hotkey/releases/tag/v0.1.2) 选择：

| 文件 | 用途 |
| --- | --- |
| [安装程序](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.2/win-voice-hotkey-0.1.2-windows-x64-setup.exe) | 按当前用户安装或升级 |
| [便携包](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.2/win-voice-hotkey-0.1.2-windows-x64-portable.zip) | 完整解压到可写目录，运行 WinVoiceHotkey.exe |
| [源码包](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.2/win-voice-hotkey-0.1.2-source.zip) | 可读源码、构建和测试脚本 |
| [SHA256SUMS.txt](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.2/SHA256SUMS.txt) | 上述三个文件的校验值 |

二进制包已包含固定版本 AutoHotkey，不用另装 Python、AutoHotkey 或开发工具。需要 Windows 自带 .NET Framework 4.x。Code → Download ZIP 是开发源码，不是可运行发行包。

1. 先在空白文本框按 Win+H，确认 Windows 语音输入本身可用。
2. 安装或完整解压，启动 WinVoiceHotkey.exe；不要在 ZIP 内运行。
3. 点击要输入的文本框，按后退侧键打开，按前进侧键关闭面板。
4. 右键通知区域图标 → 设置，可更换绑定；双击图标也可打开设置。

程序、代理和安装包**未签名**。请核对仓库地址和校验和，按设备策略处理安全提示；不要关闭安全保护或绕过组织策略。校验和证明文件一致，不等同于发布者身份签名。

```powershell
Get-FileHash .\win-voice-hotkey-0.1.2-windows-x64-setup.exe -Algorithm SHA256
```

## 设置方法

- 先选“录制打开键”或“录制关闭键”，再按下并松开一个键。键盘不支持组合绑定。
- 鼠标左/右/中/侧键和各方向滚轮，只在大录制区内操作；区域外的停止、保存、取消等按钮保持可用。
- **Esc 先停止录制，再按一次取消设置**。Esc 在设置内是安全出口，不参与录制；10 秒超时或窗口失焦也会停止。
- 录到的是草稿，点“保存启用”并确认才生效。取消或关闭窗口保留原绑定；“恢复默认”先选中 XButton1/XButton2，还需保存。
- 设置窗口打开期间暂停快捷键。普通取消恢复原绑定；若先使用 Ctrl+Alt+Shift+F12 紧急暂停，取消后仍暂停，保存才恢复。
- 详细分段指引在“使用说明”。窗口可调整大小，较小屏幕使用紧凑布局；本版没有经过最终视觉截图验收，见[验证范围](docs/TESTING.md)。

**普通输入键绑定后会占用原打字、点击或滚动功能。** 建议优先选侧键或不常用的键。可打开设置修改，或退出程序恢复原功能。

## 按键与关闭行为

打开和关闭可以设为同一个键。每次先查询真实面板：确认不存在才发送 Win+H；存在时核验真实 CloseButton 并调用 UI Automation Invoke。手动点 X 关闭后会重新查询，不按按键次数计数。不同绑定分别执行打开、关闭；关闭键在面板不存在时不打开面板。

- 支持 Windows 可捕获的键盘单键、左/右/中/侧鼠标键和上下左右滚轮。横向滚轮需硬件上报。
- 修饰键独立按下并松开时触发，原组合键行为保留；Win/Alt 系统菜单等原行为仍可能出现。
- 普通键长按不重复触发；连续滚轮脉冲合并为一个手势。
- 打开时有有界保护和面板轮询；无法确认唯一目标、扫描不完整、超时或按钮未就绪时停止动作。
- Fn、驱动/硬件拦截键和系统安全序列不保证可捕获。不接受 AutoHotkey 表达式或脚本作为配置。

关闭仍只使用真实 UIA CloseButton.Invoke，没有固定坐标、结束系统输入进程等替代路径。此前单机实测覆盖右 Shift 同键开关、XButton2 真关闭、手动 X 后重开；录音中关闭有旧版本历史接受记录，未作为本次全部设备或录音状态的专项验收。

## 配置、自启、升级和卸载

| 模式 | 程序目录 | 用户数据 |
| --- | --- | --- |
| 安装版 | `%LOCALAPPDATA%\Programs\WinVoiceHotkey` | `%APPDATA%\WinVoiceHotkey` |
| 便携版 | 解压位置 | 同目录 `data` |

新配置默认 XButton1 打开、XButton2 关闭。发行包不包含开发者或用户个人绑定、状态和日志，不主动读取其他映射工具的数据。请先退出其他占用相同键的工具。

自启默认关闭。托盘“开机自启”切换当前用户启动文件夹快捷方式；不注册系统服务、任务计划或更改系统权限。

安装程序支持带本项目标记和清单的旧安装目录原地升级，并保留用户配置和无关文件。正常退出核验失败或超时会停止，校验失败为退出码 2，超时为 3；无标记的非空目录拒绝覆盖。**如果状态显示旧 PID 或 Running=0，但托盘/进程仍在，请先从托盘退出并确认进程已消失，再升级/卸载。** 已知状态陈旧场景尚未查明，不能只凭 --stop 返回 0 认定进程已退出。

便携升级推荐解压到新目录；退出旧版后，只复制自己的 `data/config.ini`，不复制状态或诊断文件。安装版从开始菜单卸载，保留配置。运行中的 Uninstall.exe 可能留在目录，关闭后可自行删除；不要删除其他程序或目录。便携版先取消自启、从托盘退出，再删除解压目录。

## 系统与验证边界

Windows 11 x64、可用 Win+H、麦克风及相应语音语言。Windows 10、ARM64、远程桌面、受保护桌面、锁屏、管理员应用、多用户和各类驱动未完成兼容验证。Windows 更新可能改变面板结构。

本版包含退出互斥锁回调、停止等待、安装器停止门禁、真实面板候选查找和设置易用性修复。自动检查覆盖输入路由、同键状态、保存回滚、录制安全和布局，未调用实际语音服务。此前隔离环境的退出/安装回归是历史基线，未在本次启用沙盒重跑。

**已知未解决项**：曾在一次登录后观察到程序进程已启动，但状态文件仍为旧 PID/Running=0；正常退出并启动一次后恢复，原因未复现或查明。不宣称已修复此问题，也不把进程存在当作就绪证明。所有物理键鼠、不同 DPI/Windows 构建和最终视觉均未逐一实测。见[验证范围](docs/TESTING.md)。

## 隐私

工具自身不采集音频、不读取输入框文本、不上传按键记录或遥测，不提供自动更新。低层钩子只识别绑定和录制所需的键/鼠标元数据；关闭仅核验候选系统窗口和控件标识。默认不写触发历史或截图。

Windows 语音输入使用 Microsoft 在线识别，网络、麦克风和语音隐私设置由 Windows 管理；本工具不能把它变成离线，也不能替用户授权。[Microsoft 说明](https://support.microsoft.com/en-us/accessibility/windows/use-voice-typing-to-talk-instead-of-type-on-your-pc)

可选进程级支持诊断会保存有限的键名、配置路径、面板元数据和探测结果，不包含文本或音频；默认关闭、无上传。分享前请移除个人路径和运行信息。[隐私说明](docs/PRIVACY.md)

## 排查与开发

无反应时确认托盘程序在运行、设置窗口已关闭，并先检查系统 Win+H；不要同时运行其他键位映射。能打开但不能关闭时，可从托盘查看状态或手动点击系统面板 X。状态陈旧时按上文先退出再启动，不要反复启动多个副本。

可运行 `WinVoiceHotkey.exe --settings` 打开设置；`--stop` 只向具有本工具实例属性的目标发出退出请求并等待，无法据陈旧记录证明所有实例均已停止。配置损坏时，先退出程序，备份并重命名自己的 config.ini，再启动生成默认配置。

```powershell
.\scripts\Build.ps1
.\scripts\Test.ps1 -UnitOnly
```

使用 Windows x64、Windows PowerShell 5.1+ 或 PowerShell 7、系统 .NET Framework C# 编译器；无 NuGet/npm 依赖。固定依赖经正常 HTTPS 下载并校验哈希。已有 out 时先保存旧产物；完整输入钩子回归仅允许在指定隔离环境运行，不要为了测试重新启用系统功能。[构建说明](docs/BUILDING.md)

GitHub Actions 构建和运行无语音逻辑回归；新版本标签经检查后发布 Release，拒绝覆盖已存在版本或资产。

工具代码采用 [MIT](LICENSE)。未修改的 AutoHotkey 2.0.30 保留 GPL v2 及原声明，二进制包附对应完整上游源码；不重新许可第三方运行时。[第三方声明](THIRD_PARTY_NOTICES.md) · [贡献指南](CONTRIBUTING.md) · [安全报告](SECURITY.md) · [更新记录](CHANGELOG.md)