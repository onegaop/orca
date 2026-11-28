import AppKit
import SwiftUI
import InboxCore
import InboxUI

@MainActor
private final class NotchKeyablePanel: NSPanel {
    var allowsKeyFocus = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchHUDController {
    private var panel: NotchKeyablePanel?
    private var hostingController: NSHostingController<AnyView>?
    private var isExpanded = false
    private var hoverExpandTask: Task<Void, Never>?
    private var hoverCollapseTask: Task<Void, Never>?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    private let onExpandedChange: @MainActor (Bool) -> Void
    private let makeContent: @MainActor (_ hasPhysicalNotch: Bool, _ isExpanded: Bool) -> AnyView

    init(
        onExpandedChange: @escaping @MainActor (Bool) -> Void,
        makeContent: @escaping @MainActor (_ hasPhysicalNotch: Bool, _ isExpanded: Bool) -> AnyView
    ) {
        self.onExpandedChange = onExpandedChange
        self.makeContent = makeContent
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reposition(animated: false)
            }
        }
    }

    var expanded: Bool { isExpanded }

    func show() {
        ensurePanel()
        refreshContent()
        reposition(animated: false)
        panel?.orderFrontRegardless()
    }

    func hide() {
        collapse(animated: false)
        panel?.orderOut(nil)
    }

    func setExpanded(_ expand: Bool, focusInput: Bool = false) {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
        guard isExpanded != expand || focusInput else { return }
        isExpanded = expand
        panel?.allowsKeyFocus = expand
        onExpandedChange(expand)
        refreshContent()
        reposition(animated: true)
        if expand {
            installDismissMonitors()
            panel?.orderFrontRegardless()
            panel?.makeKey()
            NSApp.activate(ignoringOtherApps: false)
        } else {
            removeDismissMonitors()
            panel?.orderFrontRegardless()
        }
    }

    func toggleExpanded(focusInput: Bool = false) {
        setExpanded(!isExpanded, focusInput: !isExpanded && focusInput)
    }

    func collapse(animated: Bool = true) {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
        guard isExpanded else { return }
        isExpanded = false
        panel?.allowsKeyFocus = false
        onExpandedChange(false)
        removeDismissMonitors()
        refreshContent()
        reposition(animated: animated)
    }

    func handleHover(_ hovering: Bool) {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
        if hovering {
            guard !isExpanded else { return }
            hoverExpandTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                self?.setExpanded(true)
            }
        } else {
            guard isExpanded else { return }
            // Keep open while the user is typing in Quick Dispatch or Inline Reply.
            if panel?.firstResponder is NSTextView {
                return
            }
            hoverCollapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(480))
                guard !Task.isCancelled else { return }
                guard !(self?.panel?.firstResponder is NSTextView) else { return }
                self?.collapse(animated: true)
            }
        }
    }

    func refreshContent() {
        guard let hostingController else { return }
        hostingController.rootView = makeContent(currentHasPhysicalNotch(), isExpanded)
    }

    func teardown() {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
        removeDismissMonitors()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        panel?.close()
        panel = nil
        hostingController = nil
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NotchKeyablePanel(
            contentRect: frameForCurrentState(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingController(rootView: makeContent(currentHasPhysicalNotch(), isExpanded))
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hosting

        self.panel = panel
        self.hostingController = hosting
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func currentHasPhysicalNotch() -> Bool {
        guard let screen = targetScreen() else { return false }
        return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    private func frameForCurrentState() -> NSRect {
        guard let screen = targetScreen() else {
            return NSRect(x: 400, y: 800, width: NotchHUDMetrics.compactWidthFloating, height: NotchHUDMetrics.compactHeight)
        }
        let hasNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        let width: CGFloat = isExpanded
            ? NotchHUDMetrics.expandedWidth
            : (hasNotch ? NotchHUDMetrics.compactWidthWithNotch : NotchHUDMetrics.compactWidthFloating)
        let height: CGFloat = isExpanded
            ? NotchHUDMetrics.expandedTotalHeight
            : NotchHUDMetrics.compactHeight

        let originX = round(screen.frame.midX - width / 2)
        // Flush with the very top edge on notched MacBooks; cleanly tucked below the menu bar on external screens.
        let topY = hasNotch ? screen.frame.maxY : (screen.visibleFrame.maxY - 6)
        let originY = topY - height
        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func reposition(animated: Bool) {
        guard let panel else { return }
        let target = frameForCurrentState()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isExpanded, let panel = self.panel else { return }
                let mouseLocation = NSEvent.mouseLocation
                if !panel.frame.contains(mouseLocation) {
                    self.collapse(animated: true)
                }
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor [weak self] in
                    self?.collapse(animated: true)
                }
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
