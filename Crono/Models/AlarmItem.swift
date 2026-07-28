import Foundation
import SwiftData

/// Una alarma del usuario.
///
/// Se llama `AlarmItem` y no `Alarm` porque AlarmKit ya define un `Alarm`, y
/// tener los dos en el mismo módulo obliga a cualificar el nombre en cada uso.
/// Es la misma razón por la que las tareas son `Reminder` y no `Task`.
///
/// La hora se guarda como minutos desde medianoche, igual que el vencimiento de
/// las tareas: un `Date` obligaría a elegir un día arbitrario para representar
/// «las 7:30 de todos los días».
@Model
final class AlarmItem {
    @Attribute(.unique) var uuid: UUID

    /// Etiqueta que se ve al sonar. `""` si el usuario no puso ninguna.
    var label: String

    /// Minutos desde medianoche, 0…1439.
    var minuteOfDay: Int

    /// `WeekdaySet.rawValue`. Usar `schedule`.
    ///
    /// Reutiliza el mismo tipo con el que se programan los hábitos: «qué días de
    /// la semana» es la misma pregunta, y AlarmKit programa las repeticiones
    /// justamente con un conjunto de días.
    var scheduledWeekdaysMask: Int

    var isEnabled: Bool

    var snoozeEnabled: Bool

    var createdAt: Date

    var sortIndex: Int

    /// Identificador con el que la alarma quedó registrada en AlarmKit.
    ///
    /// `nil` mientras no esté programada en el sistema. Se guarda para poder
    /// cancelarla después: sin él, desactivar una alarma dejaría al sistema
    /// sonando por una que el usuario cree apagada.
    var systemAlarmID: UUID?

    init(
        uuid: UUID = UUID(),
        label: String = "",
        minuteOfDay: Int,
        schedule: WeekdaySet = .everyDay,
        isEnabled: Bool = true,
        snoozeEnabled: Bool = true,
        createdAt: Date = .now,
        sortIndex: Int = 0,
        systemAlarmID: UUID? = nil
    ) {
        self.uuid = uuid
        self.label = label
        self.minuteOfDay = max(0, min(minuteOfDay, 24 * 60 - 1))
        self.scheduledWeekdaysMask = schedule.rawValue
        self.isEnabled = isEnabled
        self.snoozeEnabled = snoozeEnabled
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.systemAlarmID = systemAlarmID
    }
}

// MARK: - Acceso tipado

extension AlarmItem {
    var schedule: WeekdaySet {
        get { WeekdaySet(rawValue: scheduledWeekdaysMask) }
        set { scheduledWeekdaysMask = newValue.rawValue }
    }

    var hour: Int { minuteOfDay / 60 }
    var minute: Int { minuteOfDay % 60 }
}

// MARK: - Presentación

extension AlarmItem {
    /// «7:30». Formato de 24 horas fijo.
    ///
    /// No usa `Date.FormatStyle`: eso daría «7:30 AM» en regiones de 12 horas, y
    /// aquí el reloj se muestra a lo grande — el sufijo desequilibra la fila.
    var timeText: String {
        String(format: "%d:%02d", hour, minute)
    }

    /// Texto de repetición: «Todos los días», «Lun, Mié, Vie», «Una vez».
    var scheduleText: String {
        schedule.isEmpty ? "Una vez" : schedule.displayDescription
    }

    /// Etiqueta a mostrar, con un texto por defecto si el usuario no puso nada.
    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Alarma" : trimmed
    }

    /// Solo se programa en el sistema si está activa y tiene algún día.
    ///
    /// Una alarma sin días no es «una vez» para AlarmKit: sería una alarma que
    /// no suena nunca. Que la interfaz permita dejarla vacía no significa que
    /// haya que registrarla.
    var isSchedulable: Bool {
        isEnabled && !schedule.isEmpty
    }
}

// MARK: - Consultas

enum AlarmQueries {
    /// Todas las alarmas, las más tempranas primero.
    ///
    /// Se ordena por hora y no por `sortIndex`: en una lista de alarmas lo que
    /// el usuario busca es «la de las 7», no la tercera que creó.
    static var all: FetchDescriptor<AlarmItem> {
        let order: [SortDescriptor<AlarmItem>] = [
            SortDescriptor(\AlarmItem.minuteOfDay),
            SortDescriptor(\AlarmItem.createdAt)
        ]

        return FetchDescriptor<AlarmItem>(sortBy: order)
    }
}
