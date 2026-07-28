import Foundation

/// Estado del permiso para poner alarmas.
enum AlarmAuthorization: Sendable {
    case notDetermined
    case authorized
    case denied
    /// El framework no está disponible o su API no responde como se esperaba.
    case unavailable
}

/// Quien sabe registrar alarmas en el sistema.
///
/// ## Por qué existe este protocolo
///
/// Es la frontera con AlarmKit, y está aquí por una razón concreta: los ejemplos
/// de la documentación que tengo a mano contienen errores de sintaxis, así que las
/// firmas exactas de `AlarmManager.schedule` no están confirmadas. Con el
/// protocolo por delante, el modelo, el almacén y toda la interfaz compilan y se
/// prueban sin tocar el framework; si una firma está mal, falla **un** archivo.
///
/// Es la misma idea que el envoltorio de Liquid Glass, pero hecha bien: ahí el
/// envoltorio no lo usaba nadie y era código muerto. Aquí es la única vía.
@MainActor
protocol AlarmScheduling {
    var authorization: AlarmAuthorization { get }

    /// Pide permiso al usuario y devuelve el estado resultante.
    func requestAuthorization() async -> AlarmAuthorization

    /// Registra la alarma en el sistema y devuelve el identificador con el que
    /// quedó registrada, para poder cancelarla más tarde.
    func schedule(_ item: AlarmItem) async throws -> UUID

    /// Da de baja una alarma ya registrada.
    func cancel(systemAlarmID: UUID) async throws
}

/// Implementación que no toca el sistema.
///
/// Sirve para tres cosas: los tests, las previsualizaciones, y que la app
/// funcione —guardando y listando alarmas— si el registro en el sistema falla.
/// Una alarma guardada pero sin registrar es un estado honesto: la interfaz lo
/// dice, y es mejor que no poder crearla.
@MainActor
final class NoopAlarmScheduler: AlarmScheduling {
    private(set) var scheduled: [UUID: AlarmItem] = [:]

    var authorization: AlarmAuthorization

    init(authorization: AlarmAuthorization = .authorized) {
        self.authorization = authorization
    }

    func requestAuthorization() async -> AlarmAuthorization {
        authorization
    }

    func schedule(_ item: AlarmItem) async throws -> UUID {
        let id = UUID()
        scheduled[id] = item
        return id
    }

    func cancel(systemAlarmID: UUID) async throws {
        scheduled[systemAlarmID] = nil
    }
}
