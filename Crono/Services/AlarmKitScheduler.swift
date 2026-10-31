#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
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
/// Compila y funciona contra el SDK de iOS 26.5: el diálogo de permiso del
/// sistema aparece y `NSAlarmKitUsageDescription` se muestra en él. Lo que sigue
/// **sin** verificar es que una alarma programada suene de verdad a su hora —
/// eso solo lo dice un dispositivo, no un simulador de CI.
///
/// Sigue detrás de `AlarmScheduling` por si cambia la API: el modelo, el almacén
/// y la interfaz no dependen de este archivo.
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
        let time = Alarm.Schedule.Relative.Time(hour: item.hour, minute: item.minute)
        let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(Self.weekdays(from: item.schedule))
        let schedule = Alarm.Schedule.relative(
            Alarm.Schedule.Relative(time: time, repeats: recurrence)
        )

        // Una alarma con desarme no se pospone: posponer es justo lo
        // contrario, y el hueco del botón lo ocupa «Desarmar».
        return try await register(
            item,
            schedule: schedule,
            title: item.displayLabel,
            allowsSnooze: item.snoozeEnabled && !item.requiresDisarm,
            sound: item.sound
        )
    }

    func scheduleFollowUp(of item: AlarmItem, at date: Date, ordinal: Int) async throws -> UUID {
        // El título dice qué hacer, porque es lo único que se lee medio
        // dormido: parar aquí no basta, y hay que saber adónde ir.
        let hint = item.disarmHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = hint.isEmpty
            ? "\(item.displayLabel) · Abre Crono para desarmar"
            : "\(item.displayLabel) · Escanea: \(hint)"

        // Sin Posponer: una vuelta pospuesta sería una vuelta más que el plan
        // no cuenta, y posponer es justo lo contrario de desarmar.
        return try await register(
            item,
            schedule: .fixed(date),
            title: title,
            allowsSnooze: false,
            sound: item.followUpSound
        )
    }

    private func register(
        _ item: AlarmItem,
        schedule: Alarm.Schedule,
        title: String,
        allowsSnooze: Bool,
        sound: AlarmSound
    ) async throws -> UUID {
        let id = UUID()

        // El segundo botón es «Desarmar» si la alarma lo pide, «Posponer» si
        // no lo pide y está activado, o ninguno.
        let offersDisarm = item.requiresDisarm
        let secondaryButton: AlarmButton?
        let secondaryBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior?
        let secondaryIntent: (any LiveActivityIntent)?
        if offersDisarm {
            secondaryButton = AlarmButton(text: "Desarmar", textColor: .white, systemImageName: "qrcode.viewfinder")
            secondaryBehavior = .custom
            secondaryIntent = OpenDisarmIntent(alarmID: id)
        } else if allowsSnooze {
            secondaryButton = AlarmButton(text: "Posponer", textColor: .white, systemImageName: "zzz")
            secondaryBehavior = .countdown
            secondaryIntent = nil
        } else {
            secondaryButton = nil
            secondaryBehavior = nil
            secondaryIntent = nil
        }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(
                text: "Parar",
                textColor: .white,
                systemImageName: "stop.circle"
            ),
            secondaryButton: secondaryButton,
            secondaryButtonBehavior: secondaryBehavior
        )

        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: CronoAlarmMetadata(itemID: item.uuid, label: item.displayLabel),
            tintColor: Color.accentColor
        )

        let alertSound: AlertConfiguration.AlertSound = sound.fileName.map { .named($0) } ?? .default

        let configuration = AlarmManager.AlarmConfiguration(
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: secondaryIntent,
            sound: alertSound
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
        // Un caso que no conocemos se trata como «aún no decidido», no como
        // «este aparato no puede». Mapearlo a `.unavailable` hacía que la
        // pantalla avisara de que las alarmas no sonarían justo mientras el
        // sistema estaba pidiendo el permiso — el aviso más alarmante posible,
        // y falso. `.unavailable` queda reservado para cuando AlarmKit no se
        // puede ni importar.
        @unknown default: .notDetermined
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
