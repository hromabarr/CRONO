import Foundation

extension Notification.Name {
    /// Alguien pidió desarmar desde la alerta. `RootView` lo escucha para abrir
    /// la pantalla de desarme sin esperar a su comprobación periódica.
    static let cronoDisarmRequested = Notification.Name("CronoDisarmRequested")
}

#if canImport(AlarmKit)
import AlarmKit
import AppIntents

/// El botón «Desarmar» de la alerta: para la alarma y abre Crono.
///
/// No desarma nada por sí mismo —eso exige escanear el código o resolver la
/// cuenta—; solo ahorra buscar la app medio dormido. Al abrirse, la app ve
/// que hay una alarma esperando desarme y enseña la pantalla.
struct OpenDisarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Desarmar alarma"
    static let openAppWhenRun = true
    /// Solo tiene sentido desde la alerta: no se ofrece en Atajos.
    static let isDiscoverable = false

    @Parameter(title: "Alarma")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            // Si ya no suena, no hay nada que parar y no es un error.
            try? AlarmManager.shared.stop(id: id)
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .cronoDisarmRequested, object: nil)
        }
        return .result()
    }
}
#endif
