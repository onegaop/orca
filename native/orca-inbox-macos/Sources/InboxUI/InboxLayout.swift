import SwiftUI
import InboxCore

private struct ReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

public extension EnvironmentValues {
    var inboxReduceTransparencyOverride: Bool? {
        get { self[ReduceTransparencyOverrideKey.self] }
        set { self[ReduceTransparencyOverrideKey.self] = newValue }
    }
}

public enum InboxMetrics {
    public static let panelWidth: CGFloat = 420
    public static let panelHeight: CGFloat = 492

    public static let horizontalPadding: CGFloat = 16
    public static let footerHeight: CGFloat = 48

    // Unified vertical alignment grid for Project -> Workspace -> Agent
    public static let projectIconWidth: CGFloat = 16
    public static let projectIconGap: CGFloat = 8

    public static let workspaceIndent: CGFloat = 14
    public static let workspaceIconWidth: CGFloat = 14
    public static let workspaceIconGap: CGFloat = 6

    public static let rowIndent: CGFloat = 24
    public static let rowIconWidth: CGFloat = 16
    public static let rowIconGap: CGFloat = 8

    // Fixed right-side columns so badges and timestamps never drift or get squeezed
    public static let statusBadgeMinWidth: CGFloat = 46
    public static let statusBadgeCornerRadius: CGFloat = 5.5
    public static let trailingColumnGap: CGFloat = 8
    public static let timeColumnWidth: CGFloat = 46
}

struct InboxActionButtonStyle: ViewModifier {
    let reduceTransparency: Bool
    let isCircular: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            if isCircular {
                content
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            } else {
                content
                    .buttonStyle(.bordered)
            }
        } else {
            if isCircular {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            } else {
                content
                    .buttonStyle(.glass)
            }
        }
    }
}

extension View {
    func inboxActionButtonStyle(reduceTransparency: Bool, isCircular: Bool = false) -> some View {
        modifier(InboxActionButtonStyle(reduceTransparency: reduceTransparency, isCircular: isCircular))
    }
}

enum InboxPalette {
    static func blockedFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.86, green: 0.22, blue: 0.22)
            : Color(red: 0.78, green: 0.12, blue: 0.14)
    }

    static func blockedInk(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.45, blue: 0.43)
            : Color(red: 0.75, green: 0.10, blue: 0.12)
    }

    static func waitingInk(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.68, blue: 0.28)
            : Color(red: 0.68, green: 0.36, blue: 0.0)
    }

    static func workingInk(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.45, green: 0.72, blue: 1.0)
            : Color(red: 0.08, green: 0.38, blue: 0.78)
    }

    static func doneInk(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.42, green: 0.84, blue: 0.54)
            : Color(red: 0.12, green: 0.50, blue: 0.22)
    }

    static func iconColor(for kind: AgentStateKind, colorScheme: ColorScheme) -> Color {
        switch kind {
        case .blocked: blockedInk(colorScheme: colorScheme)
        case .waiting: waitingInk(colorScheme: colorScheme)
        case .working: workingInk(colorScheme: colorScheme)
        case .done: doneInk(colorScheme: colorScheme)
        case .unknown: .secondary
        }
    }
}
