import SwiftUI
import InboxCore

public struct InboxQuickDispatchBar: View {
    public let workspaces: [DispatchWorkspaceOption]
    public let agents: [InstalledAgentOption]
    @Binding public var selectedWorktreeId: String
    @Binding public var selectedAgentId: String
    @Binding public var promptText: String
    public let isDispatching: Bool
    public let focusTrigger: Int
    public let onDispatch: () -> Void

    @FocusState private var isPromptFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.inboxReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    public init(
        workspaces: [DispatchWorkspaceOption],
        agents: [InstalledAgentOption],
        selectedWorktreeId: Binding<String>,
        selectedAgentId: Binding<String>,
        promptText: Binding<String>,
        isDispatching: Bool,
        focusTrigger: Int = 0,
        onDispatch: @escaping () -> Void
    ) {
        self.workspaces = workspaces
        self.agents = agents
        self._selectedWorktreeId = selectedWorktreeId
        self._selectedAgentId = selectedAgentId
        self._promptText = promptText
        self.isDispatching = isDispatching
        self.focusTrigger = focusTrigger
        self.onDispatch = onDispatch
    }

    private var canSubmit: Bool {
        !isDispatching
            && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedWorktreeId.isEmpty
            && !selectedAgentId.isEmpty
    }

    private var selectedWorkspaceLabel: String {
        workspaces.first(where: { $0.worktreeId == selectedWorktreeId })?.displayLabel
            ?? (workspaces.isEmpty ? "暂无工作区" : "选择工作区")
    }

    private var selectedAgentLabel: String {
        agents.first(where: { $0.id == selectedAgentId })?.label ?? selectedAgentId.capitalized
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField(
                        "一句话派活给后台 Agent（回车直接开跑）…",
                        text: $promptText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($isPromptFocused)
                    .disabled(isDispatching)
                    .onSubmit {
                        if canSubmit { onDispatch() }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isPromptFocused
                                ? Color.accentColor.opacity(0.65)
                                : Color(nsColor: .separatorColor).opacity(0.5),
                            lineWidth: isPromptFocused ? 1.2 : 0.75
                        )
                }

                Button(action: onDispatch) {
                    Group {
                        if isDispatching {
                            ProgressView().controlSize(.mini)
                        } else {
                            HStack(spacing: 4) {
                                Text("派发")
                                Image(systemName: "return")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6.5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSubmit)
                .help("在所选工作区后台启动新 Agent 会话")
            }

            HStack(spacing: 6) {
                Menu {
                    if workspaces.isEmpty {
                        Text("打开 Orca 工作区后可选择")
                    } else {
                        ForEach(workspaces) { option in
                            Button {
                                selectedWorktreeId = option.worktreeId
                            } label: {
                                HStack {
                                    Text(option.displayLabel)
                                    if option.worktreeId == selectedWorktreeId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(selectedWorkspaceLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.7)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: 220, alignment: .leading)
                .disabled(workspaces.isEmpty || isDispatching)

                Menu {
                    ForEach(agents) { agent in
                        Button {
                            selectedAgentId = agent.id
                        } label: {
                            HStack {
                                Text(agent.label)
                                if agent.id == selectedAgentId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text(selectedAgentLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.7)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(isDispatching)

                Spacer(minLength: 4)

                Text("⌥Space 随时呼出")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, InboxMetrics.horizontalPadding)
        .padding(.vertical, 10)
        .background(
            reduceTransparency
                ? Color(nsColor: .controlBackgroundColor).opacity(0.5)
                : Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.025)
        )
        .onChange(of: focusTrigger) { _, _ in
            isPromptFocused = true
        }
    }
}
