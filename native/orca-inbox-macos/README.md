# Orca 任务收件箱

v0.4.0，macOS 26+ SwiftUI 菜单栏伴侣。保留系统 `MenuBarExtra`，通过本机已安装的 Orca 查看所选本机或配对远程主机的 Agent 状态。它不创建工作区，也不管理 Agent。

- 状态：待处理（阻塞优先，然后等待输入）、进行中、已完成。
- 菜单栏数字是**当前所选主机**的阻塞 + 等待输入数量。首次读取显示 `…`，没有缓存且连接失败显示 `!`；旧数据用时钟图标及 `~` 标记（例如 `3~`）。截断列表的数字带 `+`，表示数量下限。悬停可查看主机和状态，断线不会显示成零待办。
- 菜单栏与面板共用一个 Store、一条串行轮询：启动、打开面板或切换主机时立即读取；打开时每 15 秒刷新，关闭时每 60 秒刷新。只查询所选主机，不轮询所有远程主机。手动刷新复用同一条轮询，不并发堆积请求。
- 每个主机单独保留内存缓存。切换主机时立即显示其缓存（标为旧数据）或加载状态；失败保留该主机的结果。超过 120 秒没有成功同步也标为旧数据。主机发现失败或选中环境暂时不在列表里时，不会偷偷切回本机。
- 层级：项目 → 工作区 → Agent；Git 工作区用 Orca 的工作区标识归类，不按分支名称合并，也支持文件夹工作区。
- 有完整稳定标识的任务可以点击打开**原会话**；右键仍可复制 Orca 会话 ID、打开此会话或打开 Orca。缺少稳定会话 ID、使用旧版数字窗格 ID 或其他无效字段时，显示“缺少完整会话标识”，保留右键入口，不声称能直接定位。
- 跳转使用 `orca://inbox/session?environment=<HostTarget.id>&workspace=<worktreeId>&pane=<paneKey>&id=<orcaSessionId>`，记录带执行主机时追加 `host=<hostId>`。通过 `URLComponents` 编码，另将字面量 `+` 转义为 `%2B`，再用 `NSWorkspace.open(_:withApplicationAt:configuration:)` 交给解析出的同一个 Orca.app，避免多个版本竞争默认协议处理器。接收端仍会核对实际会话标识后定位，不把复用的窗格当作原会话。
- 数据源：本机 Orca 自带的 `host list --json` 和 `agent list --environment <所选主机> --json`；不调用 `agent read`、不保存或展示回复正文、不发通知。连接错误显示在面板，找不到应用或启动失败也显示明确错误。
- 启动入口：`~/Applications/Orca Inbox.app`。不配置登录启动。底部“打开 Orca”继续打开主窗口。

本地重建安装：`./install.sh`（同时保留 `./install-mini.sh` 兼容入口）。构建：`swift build --disable-sandbox --product OrcaInbox`。纯逻辑检查：`swift test --disable-sandbox --filter 'sessionDestination|inFlightHostSwitch'`；这些检查不会启动 Orca 或 Inbox 界面。`--check-live --environment <id>` 可只读检查所选环境的 CLI 连通性。

回归时确认：切换本机/远程后计数只跟随当前主机；关闭面板后计数仍更新；离线时显示未知或旧数据；点击任务进入同一环境、工作区及稳定会话；缺标识任务保留复制和打开 Orca。真实菜单栏、冷启动/已运行 Orca 的端到端跳转仍需在允许的独立图形环境验收。
