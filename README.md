# Win Voice Hotkey

**把 Windows 语音输入放到顺手的一颗按键上。**

版本 **0.1.4**，面向 Windows 11 x64。默认鼠标后退侧键 **XButton1** 唤醒 Win+H，前进侧键 **XButton2** 关闭语音面板。可在设置中改成单个键盘键、其他鼠标键或滚轮，也可把开关绑定为同一键。升级保留你已选的绑定，不会强制改成默认键。

## 下载与开始

从 [v0.1.4 Release](https://github.com/SuTaiHui1/win-voice-hotkey/releases/tag/v0.1.4) 下载：

| 文件 | 用途 |
| --- | --- |
| [安装包](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.4/win-voice-hotkey-0.1.4-windows-x64-setup.exe) | 当前用户安装；已有安装版可原地升级 |
| [便携包](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.4/win-voice-hotkey-0.1.4-windows-x64-portable.zip) | 完整解压到可写目录，运行 WinVoiceHotkey.exe |
| [源码包](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.4/win-voice-hotkey-0.1.4-source.zip) | 可读源码、文档、构建与测试脚本 |
| [SHA256SUMS.txt](https://github.com/SuTaiHui1/win-voice-hotkey/releases/download/v0.1.4/SHA256SUMS.txt) | 本次发行文件的 SHA-256 |

二进制包已包含固定版本 AutoHotkey，无需另装 Python、AutoHotkey 或开发工具；辅助代理依赖 Windows 自带 .NET Framework 4.x。GitHub 的 Code → Download ZIP 是开发源码，不是可直接运行的发行包。

1. 在独立空白文本框手动按 Win+H，先确认 Windows 语音输入、麦克风与联网条件可用。
2. 安装或完整解压后运行 WinVoiceHotkey.exe，不要直接在 ZIP 内运行。
3. 把光标放到目标文本框，按打开键；要关闭时按关闭键，或在设置中把两者设为同一键。
4. 右键托盘图标 → 设置（或双击图标）修改绑定；托盘“查看状态”用于手动排查。

程序、代理和安装包均**未签名**。先核对仓库来源及同一 Release 的校验文件；校验不等于发行者代码签名。无需为本工具关闭系统防护或改变组织安全策略。

```powershell
Get-FileHash .\win-voice-hotkey-0.1.4-windows-x64-setup.exe -Algorithm SHA256
```

## 0.1.4 的中文听写行为

通过本程序唤醒时，先确认**原目标编辑窗口**使用简体中文输入语言（zh-CN），再发送 Win+H。即使当前是英文，也会明确请求中文布局并核实生效，不靠固定次数 Win+空格猜测语言。

- 需要系统已有可用的简体中文输入法。缺失、切换超时、目标焦点变化或用户中途主动切换语言时，取消本次唤醒；不自动安装语言包、删除语言或更改系统默认语言。
- 唤醒时切到的中文在关闭后保留，**不会自动恢复之前的英文**；用户仍可自行用 Win+空格切换。准备期间不抢回新焦点，也不覆盖主动语言选择。
- 中文准备的成功、准备中、失败和取消都**不弹窗口、气泡或提示条**。失败仍保留真实诊断状态；没有提示不代表语音已启动。
- “查看状态”中的语言确认只说明目标语言检查结果，不代表 Windows 面板已经完整出现或识别成功。
- 直接手动按 Win+H 仍由 Windows 自己决定语言，不经过本程序的中文保障。

## 按需代理与内存

主程序待机时不启动 .NET/UI Automation 代理。需要面板查询或关闭时按需启动；确认面板已关闭/不存在、没有在途请求或打开/语言准备过程，且空闲约 **10 秒**后，再确认一次面板状态并正常退出代理。面板存在或结果不确定时保留代理。代理崩溃后记录失败，下次请求恢复，不反复后台拉起。

**待机时找不到 VoicePanelBroker.exe 是正常状态。** 主程序就绪表示能接收请求，不能据此认定语音正在录制。设置、同键开关与自启不依赖代理一直驻留。

一台 Windows 11 x64 电脑按相同统计口径测得：待机自有进程工作集合计由约 **68 MB 降至17 MB**；私有提交由约28 MB降至4 MB。代理存活的无输入夹具仍约67 MB工作集。首次代理就绪约 **251 ms**，热查询约15 ms；**251 ms不是语音面板完整弹出时间**。这些是单机样本，不是跨设备承诺，也不代表真实录音/识别期间的系统总占用。Windows 的 Win+H、TextInputHost 和识别服务未计入本工具。详见[验证范围](docs/TESTING.md)。

## 绑定与开关

- 设置中选择“录制打开键”或“录制关闭键”，再按下并松开单个键；不接受组合键、AHK表达式或脚本作为配置。
- 鼠标左/中/右/侧键和滚轮只在专用录制区域捕获；停止、保存、取消等按钮仍可操作。
- Esc先停止录制，再按一次取消设置；失焦或10秒超时也停止录制。结果是草稿，点“保存并应用”才生效；关闭/取消保留原绑定。
- 设置窗口暂停映射。紧急暂停可用 Ctrl+Alt+Shift+F12，释放按键后恢复或调整设置。
- 同键开关先查询真实面板：不存在才准备中文并打开，存在时调用真实 UIA CloseButton.Invoke 关闭。关闭键不会因面板不存在而反向打开。
- 冷启动准备中的同键重复操作可取消尚未发送的打开请求；短时间重复按键不会无限排队。手动点击面板 X 后，下次重新查询。
- 普通键绑定会占用其原打字/点击/滚动功能；建议选择侧键或不常用键。退出本程序可解除映射。Fn、固件快捷键和系统安全序列不保证可捕获。

更详细的设置、升级和排查步骤见[使用说明](docs/USAGE.md)。

## 安装、升级、自启与卸载

| 模式 | 程序目录 | 配置/状态/日志 |
| --- | --- | --- |
| 安装版 | `%LOCALAPPDATA%\Programs\WinVoiceHotkey` | `%APPDATA%\WinVoiceHotkey` |
| 便携版 | 完整解压位置 | 同目录 `data` |

安装包支持对带有本项目标记和清单的目录原地升级：正常停止旧实例后再替换，保留用户配置与无关文件；停止核实失败或超时即中止，不覆盖历史版本资产。便携版建议解压到新目录，正常退出旧版，只迁移自己的 `data/config.ini`，不复制运行状态或请求文件。

自启默认关闭；托盘“开机启动”只切换当前用户启动文件夹里的快捷方式，不注册服务、计划任务或管理员权限。移动便携版前先取消其旧自启，移动后按需重新启用。

安装版从 Windows 已安装应用、开始菜单或程序目录的 Uninstall.exe 卸载；程序文件按清单移除，配置/日志默认保留。便携版先取消自启并退出，再删除解压目录。具体见[安装与卸载步骤](docs/USAGE.md#安装升级与卸载)。

## 系统条件、限制与排查

需要 Windows 11 x64、可工作的 Win+H、麦克风权限、简体中文输入法及 Windows 语音输入所需的网络/在线识别条件。程序不自带识别模型，也不改变系统面板。

本轮自动化和隔离包测试通过，但**真实物理侧键、系统语音面板及中文转写组合尚未经用户验收**。没有将历史单机测试或先前登录记录当作0.1.4的新验收。Windows 10、ARM64、远程桌面、安全桌面、管理员应用、不同输入框/TSF实现、多语言、多DPI及长期录音稳定性未全面验证。

没有弹提示时先手动查看托盘状态。`BrokerMode=on_demand`、`BrokerPhase=idle`、`CloseBrokerPID=0`是正常待机；`LanguageResult`和`BrokerLastError`用于区分语言未确认、焦点变化与辅助进程故障。请先测试系统自己的 Win+H，再查[故障排查](docs/TROUBLESHOOTING.md)，不要同时运行多个占用相同按键的映射工具。

## 隐私与开发

本程序不录制或上传音频，不读取输入框文字，不提供遥测或自动更新。低层钩子处理绑定/录制键的元数据；语言保障仅读取原目标窗口、焦点、线程及语言布局标识，显式切换该目标的输入语言；关闭使用候选窗口标识与真实 UIA Invoke。必要本地生命周期日志和状态不包含听写文字或音频。[隐私说明](docs/PRIVACY.md)

Windows 语音输入使用 Microsoft 的语音识别；其麦克风、联网及隐私选项由 Windows 管理。[Microsoft 语音键入说明](https://support.microsoft.com/en-us/accessibility/windows/use-voice-typing-to-talk-instead-of-type-on-your-pc)

```powershell
.\scripts\Check-PublicContent.ps1
.\scripts\Build.ps1
.\scripts\Test.ps1 -UnitOnly
.\scripts\Test-Lifecycle.ps1
```

Windows x64、PowerShell 5.1+或7、系统 .NET Framework C# 编译器；无 NuGet/npm 依赖。代理/安装包无输入测试另见[构建](docs/BUILDING.md)和[测试](docs/TESTING.md)。CI运行无麦克风回归，标签发布拒绝覆盖已有Release。

项目自身代码为 [MIT](LICENSE)。未修改的 AutoHotkey 2.0.30 按 GPL v2 原许可分发，二进制包附许可及对应上游源码。[第三方声明](THIRD_PARTY_NOTICES.md) · [更新记录](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md) · [安全说明](SECURITY.md)