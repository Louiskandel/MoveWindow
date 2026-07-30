import Foundation
import UserNotifications

struct ActivityReminderService {
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func scheduleCheckInReminder(for session: ActivitySession) async throws {
        let reminderDate = session.plannedEnd.addingTimeInterval(15 * 60)
        guard reminderDate > Date() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "How did your \(session.activity.rawValue.lowercased()) feel?"
        content.body = "Check in with MoveWindow to make your MoveDNA recommendations more personal."
        content.sound = .default
        content.userInfo = ["activitySessionID": session.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: session),
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(for session: ActivitySession) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: session)]
        )
    }

    private func notificationIdentifier(for session: ActivitySession) -> String {
        "movedna-check-in-\(session.id.uuidString)"
    }
}
