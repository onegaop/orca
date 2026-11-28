# Orca 任务收件箱（v0.5.0）

macOS 26+ 原生 Agent 指挥伴侣（AppKit + SwiftUI Liquid Glass），支持**刘海灵动岛（Notch HUD）**与**菜单栏弹窗**双形态自由切换，并提供全局快捷键 **`⌥Space`** 随时呼出。

## 核心能力

- **平铺高密度 Triage 收件箱**：按「收件箱（阻塞顶置 + 等回复 + 未读完成） / 运行中 / 全部」组织卡片，直接展示 `lastAssistantMessage` 纯文本摘要，并支持按需展开查看最近对话（`orca agent read`）。
- **已读归档机制**：已完成的任务支持单条归档或“一键清空已完成”，持久化在本地 `UserDefaults`；同一会话若后续产生更新的回复（`updatedAt` 变新），会自动重新浮现为未读；阻塞/等待项永远置顶不被隐藏。
- **顶部“一句话快速派活”**：直接选择工作区与已安装 Agent（记住上次选择），回车调用 `orca agent launch` 在后台开跑，无需切回 Orca 主窗口。
- **原地快速回复与一键审批**：通过 `orca agent requests`、`orca agent reply` 与 `orca agent respond` 读取当前待确认的权限审批或提问选项，支持在卡片内一键批准/拒绝/选选项或直接发送追问。
- **刘海灵动岛 & 顶部悬浮胶囊**：在带刘海的 MacBook 上自动贴合刘海两侧显示运行与待处理状态，悬停或点击丝滑展开完整指挥台；外接无刘海显示器自动切换为顶部居中悬浮药丸；在底栏“更多设置”中可随时切换为“仅菜单栏”模式。
- **高频轻量同步与轻提醒**：展开时每 3 秒同步，收起时每 10 秒同步；检测到新阻塞、等待或完成时发送可选的 macOS 系统通知（点击通知直达对应 Orca 会话）。
- **精准跳转**：保留 `orca://inbox/session?...` 稳定会话定位与多主机（本机 / 配对远程主机）独立缓存。

## 构建与测试

- 本地重建安装：`./install.sh`（同步保留 `./install-mini.sh`）
- 调试构建：`swift build --disable-sandbox --product OrcaInbox`
- 单元测试：`swift test --disable-sandbox`
- 连通性自检：`.build/debug/OrcaInbox --check-live --environment local`
