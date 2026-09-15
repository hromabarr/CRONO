import Foundation

/// Quien sabe programar los avisos de vencimiento de las tareas.
///
/// Mismo aislamiento que `AlarmScheduling`, y por la misma razón: el modelo, el
/// almacén y la interfaz no deben depender de un framework del sistema que aquí
/// no se puede probar. Si `UserNotifications` cambia, falla un archivo.
///
/// Es distinto de las alarmas a propósito. Una alarma atraviesa el silencio y el
/// modo de concentración; una notificación de tarea no, y no debe fingir que sí.
/// Son dos promesas distintas al usuario y se cumplen con dos frameworks.
protocol ReminderNotifying: Sendable {
    var authorization: AlarmAuthorization { get async }

    func requestAuthorization() async -> AlarmAuthorization

    /// Programa el aviso de una tarea. Si ya había uno para esa tarea, lo
    /// reemplaza.
    func schedule(_ request: ReminderNotificationRequest) async

    /// Cancela el aviso de una tarea, la haya o no.
    func cancel(reminderID: UUID) async
}

/// Lo que hace falta para programar un aviso, sin arrastrar el modelo.
///
/// Se pasa un valor y no el `Reminder` porque `Reminder` es una clase de
/// SwiftData atada al hilo principal, y esto cruza a un framework asíncrono.
struct ReminderNotificationRequest: Sendable {
    let reminderID: UUID
    let title: String
    let body: String
    let fireDate: Date
}

/// Implementación que no toca el sistema. Para tests y previsualizaciones.
actor NoopReminderNotifier: ReminderNotifying {
    private(set) var scheduled: [UUID: ReminderNotificationRequest] = [:]
    private var state: AlarmAuthorization

    init(authorization: AlarmAuthorization = .authorized) {
        self.state = authorization
    }

    var authorization: AlarmAuthorization { state }

    func requestAuthorization() async -> AlarmAuthorization { state }

    func schedule(_ request: ReminderNotificationRequest) async {
        scheduled[request.reminderID] = request
    }

    func cancel(reminderID: UUID) async {
        scheduled[reminderID] = nil
    }
}
