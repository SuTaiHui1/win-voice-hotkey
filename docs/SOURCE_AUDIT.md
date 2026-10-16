# 发布来源与边界审查

运行入口为 `src/app/WinHGate.ahk`，包含 KeyCatalog、KeyboardObserver → MouseObserver、GlobalModifierTap、KeySettings → CloseBindings、GlobalRuntime、CloseBrokerRuntime → PanelWindowTracker。状态入口只包含 AppPaths 与 KeyCatalog。C# 关闭进程由 VoicePanelCore 与 VoicePanelBroker 构建；Launcher 和 Installer 是发行整理时新增的宿主程序。

所提供本地原型文档将该功能描述为单键 AutoHotkey Win+H 原型。当前纳入的 AHK/C# 文件没有原有项目 LICENSE、版权头或外部代码来源标注。没有发现当前入口引用 CapsWriter 客户端/服务器、模型或第三方 UIA-v2 代码；相关历史文件均排除。保留代码来源于这个本地原型，不能仅因工作目录曾带 CapsWriter 名称，就推断它继承了 CapsWriter 的许可；同样，没有版权头也不能单独证明所有代码原创。工具代码许可证仍由项目所有者确认。

独立打包的第三方只有未修改的 AutoHotkey 2.0.30 解释器，其摘要、完整许可、对应源码与上游声明按原许可保留。源码归档带有其自身的嵌入库与原始声明，未作为本工具原创代码重许可。

发行整理的必要改动：运行配置/状态与就绪文件转入独立数据目录；更改本项目窗口属性名称以隔离旧安装；关闭触发/窗口详细日志；增加按用户自启、启动宿主、隔离冒烟测试和安装/卸载。语义关闭仍只调用真实 Windows 语音面板 CloseButton.Invoke，不加入固定坐标、WM_CLOSE 或结束系统进程的备用路径。

公开内容按源码/文档清单组装；不拷贝用户 config、运行状态、录音、聊天/窗口数据、历史截图、原始验收报告、备份或其他项目文件。测试结果仅包含断言、计数器与布尔结果。模式扫描与人工审查互相补充；不以扫描结果宣称不存在任何安全问题。
