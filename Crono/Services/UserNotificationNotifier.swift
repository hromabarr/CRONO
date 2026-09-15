#if canImport(UserNotifications)
import Foundation
import UserNotifications

/// La única pieza de la app que toca `UserNotifications`.
///
/// A diferencia de AlarmKit, aquí no hace falta ninguna clave en el Info.plist:
/// las notificaciones locales se piden con `requestAuthorization(options:)` y el
/// sistema redacta el diálogo.
actor UserNotificationNotifier: ReminderNotifying {
    private let center = UNUserNotificationCenter.current()

    var authorization: AlarmAuthorization {
        get async {
            let settings = await center.notificationSettings()
            return Self.map(settings.authorizationStatus)
        }
    }

    func requestAuthorization() async -> AlarmAuthorization {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            return .unavailable
        }
    }

    func schedule(_ request: ReminderNotificationRequest) async {
        // Una fecha ya pasada no se programa: iOS la dispararía al instante, y
        // recibir el aviso de una tarea que venció ayer al abrir la app es ruido,
        // no un recordatorio.
        guard request.fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = request.title
        if !request.body.isEmpty { content.body = request.body }
        content.sound = .default

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)

        // El identificador es el de la tarea, así que reprogramar reemplaza el
        // aviso anterior en lugar de acumular duplicados.
        let notification = UNNotificationRequest(
            identifier: request.reminderID.uuidString,
            content: content,
            trigger: trigger
        )

        try? await center.add(notification)
    }

    func cancel(reminderID: UUID) async {
        let id = reminderID.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    private static func map(_ status: UNAuthorizationStatus) -> AlarmAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        // Igual que en las alarmas: un caso desconocido es «aún no decidido»,
        // no «este aparato no puede».
        @unknown default: .notDetermined
        }
    }
}
#endif
