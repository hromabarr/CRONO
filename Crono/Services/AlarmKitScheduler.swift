#if canImport(AlarmKit)
import AlarmKit
import Foundation
import SwiftUI

/// Metadatos que viajan con la alarma en el sistema.
///
/// AlarmKit los usa para la Live Activity de la Isla Dinámica y la pantalla
/// bloqueada. Se guarda el `uuid` de nuestra `AlarmItem` para poder relacionar
/// una alarma del sistema con la nuestra.
struct CronoAlarmMetadata: AlarmMetadata {
    let itemID: UUID
    let label: String
}

/// La única pieza de la app que toca AlarmKit.
///
/// > Importante: las firmas de `AlarmManager.schedule` y de los tipos de
/// > presentación son una reconstrucción, no están verificadas. La documentación
/// > que tengo a mano trae ejemplos con errores de sintaxis, así que si algo de
/// > este archivo no compila, el mensaje del compilador es más fiable que estos
/// > comentarios: la forma correcta está en la definición del framework.
/// >
/// > Todo lo demás —modelo, almacén, interfaz— va detrás de `AlarmScheduling` y
/// > no depende de que esto sea exacto.
@MainActor
final class AlarmKitScheduler: AlarmScheduling {

    var authorization: AlarmAuthorization {
        Self.map(AlarmManager.shared.authorizationState)
    }

    func requestAuthorization() async -> AlarmAuthorization {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return Self.map(state)
        } catch {
            // Falla en silencio si falta `NSAlarmKitUsageDescription` en el
            // Info.plist. Está puesta, pero si alguien la quita conviene que la
            // app lo trate como "no disponible" y no como "denegado".
            return .unavailable
        }
    }

    func schedule(_ item: AlarmItem) async throws -> UUID {
        let id = UUID()

        let time = Alarm.Schedule.Relative.Time(hour: item.hour, minute: item.minute)
        let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(Self.weekdays(from: item.schedule))
        let schedule = Alarm.Schedule.relative(
            Alarm.Schedule.Relative(time: time, repeats: recurrence)
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: item.displayLabel),
            stopButton: AlarmButton(
                text: "Parar",
                textColor: .white,
                systemImageName: "stop.circle"
            ),
            secondaryButton: item.snoozeEnabled
                ? AlarmButton(text: "Posponer", textColor: .white, systemImageName: "zzz")
                : nil,
            secondaryButtonBehavior: item.snoozeEnabled ? .countdown : nil
        )

        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: CronoAlarmMetadata(itemID: item.uuid, label: item.displayLabel),
            tintColor: Color.accentColor
        )

        let configuration = AlarmManager.AlarmConfiguration(
            schedule: schedule,
            attributes: attributes
        )

        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        return id
    }

    func cancel(systemAlarmID: UUID) async throws {
        try AlarmManager.shared.cancel(id: systemAlarmID)
    }

    // MARK: - Conversiones

    private static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    /// Traduce nuestra máscara de días a los días de AlarmKit.
    ///
    /// `WeekdaySet` usa la convención de Foundation (1 = domingo … 7 = sábado);
    /// AlarmKit usa `Locale.Weekday`, que es un enum con nombre. La conversión va
    /// aquí y no en el modelo: `WeekdaySet` no debe saber que AlarmKit existe.
    private static func weekdays(from schedule: WeekdaySet) -> [Locale.Weekday] {
        var result: [Locale.Weekday] = []
        for weekday in schedule.orderedWeekdays {
            switch weekday {
            case 1: result.append(.sunday)
            case 2: result.append(.monday)
            case 3: result.append(.tuesday)
            case 4: result.append(.wednesday)
            case 5: result.append(.thursday)
            case 6: result.append(.friday)
            case 7: result.append(.saturday)
            default: break
            }
        }
        return result
    }
}
#endif
