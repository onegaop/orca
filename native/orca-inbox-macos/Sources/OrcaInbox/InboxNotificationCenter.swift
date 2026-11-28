import AppKit
import Foundation
import InboxCore
import UserNotifications

@MainActor
final class InboxNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private let onOpenDestination: @MainActor (URL?) -> Void
    private var available = false
    private var authorized = false

    init(onOpenDestination: @escaping @MainActor (URL?) -> Void) {
        self.onOpenDestination = onOpenDestination
        super.init()
        // UNUserNotificationCenter requires a bundled .app with a bundle identifier.
        guard Bundle.main.bundleIdentifier != nil else { return }
        available = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            self.authorized = granted
        }
    }

    func post(_ events: [InboxAlertEvent]) {
        guard available, authorized else { return }
        let center = UNUserNotificationCenter.current()
        for event in events.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = event.kind == .blocked ? .default : nil
            if let url = event.destinationURL {
                content.userInfo = ["destinationURL": url.absoluteString]
            }
            let request = UNNotificationRequest(
                identifier: "orca-inbox-\(event.rowID)-\(event.kind.rawValue)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let urlString = response.notification.request.content.userInfo["destinationURL"] as? String
        let url = urlString.flatMap(URL.init(string:))
        await MainActor.run {
            self.onOpenDestination(url)
        }
    }
}
