import Foundation
import UserNotifications

/// Retained delegate also presents route notifications when the app is open.
final class RouteNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RouteNotifications()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do { _ = try await center.requestAuthorization(options:[.alert,.sound]) }
        catch { LogManager.shared.addErrorLog("Notification permission failed: \(error.localizedDescription)") }
    }
    func routeStarted(_ name: String) {
        let content = UNMutableNotificationContent()
        content.title = "Route movement started"
        content.body = "MobileGhost is now moving along \(name)."
        content.sound = .default
        let request = UNNotificationRequest(identifier:UUID().uuidString,content:content,trigger:nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { LogManager.shared.addErrorLog("Route notification failed: \(error.localizedDescription)") }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner,.list,.sound])
    }
}
