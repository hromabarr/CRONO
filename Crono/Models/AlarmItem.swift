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

    // MARK: - Desarme e insistencia
    //
    // Las tres propiedades no opcionales llevan su valor por defecto **en la
    // declaración**, no solo en el `init`. No es estilo: una migración ligera
    // necesita saber con qué rellenar las filas que ya existen, y sin ese valor
    // no puede añadir la columna.

    /// `DisarmMethod.rawValue`. `nil` es «solo parar». Usar `disarmMethod`.
    var disarmMethodRaw: String?

    /// Qué hay que escanear, con las palabras del usuario: «el bote de champú».
    ///
    /// Sin esto la función es cruel. A las siete de la mañana, medio dormido, no
    /// te acuerdas de qué código registraste hace tres semanas, y la alarma
    /// vuelve cada tres minutos mientras lo piensas.
    var disarmHint: String = ""

    /// Minutos entre una vuelta y la siguiente. 0 = no insiste.
    var insistenceIntervalMinutes: Int = 0

    /// Cuántas veces vuelve, sin contar la original.
    var insistenceRepeats: Int = 0

    /// Los identificadores con los que quedaron registradas las vueltas,
    /// separados por comas.
    ///
    /// Se guardan como cadena y no como `[UUID]` por lo mismo que el color y la
    /// repetición: el resto de los modelos guarda los tipos con valor como
    /// primitivos, y así se lee en el depurador sin tener que descifrarlo.
    ///
    /// Hay que guardarlos porque desarmar consiste precisamente en cancelarlos,
    /// y sin ellos el sistema seguiría sonando por una alarma que el usuario
    /// cree ya resuelta.
    var followUpAlarmIDsRaw: String = ""

    init(
        uuid: UUID = UUID(),
        label: String = "",
        minuteOfDay: Int,
        schedule: WeekdaySet = .everyDay,
        isEnabled: Bool = true,
        snoozeEnabled: Bool = true,
        createdAt: Date = .now,
        sortIndex: Int = 0,
        systemAlarmID: UUID? = nil,
        disarmMethod: DisarmMethod = .stop,
        disarmHint: String = "",
        insistence: InsistencePlan = .none
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
        self.disarmMethodRaw = disarmMethod == .stop ? nil : disarmMethod.rawValue
        self.disarmHint = disarmHint
        self.insistenceIntervalMinutes = insistence.intervalMinutes
        self.insistenceRepeats = insistence.repeats
        self.followUpAlarmIDsRaw = ""
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

    /// Qué hay que hacer para que la alarma deje de volver.
    ///
    /// Un valor guardado que no se sepa leer cae a `.stop`, no a un método
    /// imposible de cumplir: ante un dato corrupto, la alarma se comporta como
    /// una normal en vez de quedarse imposible de desarmar.
    var disarmMethod: DisarmMethod {
        get { disarmMethodRaw.flatMap(DisarmMethod.init(rawValue:)) ?? .stop }
        set { disarmMethodRaw = newValue == .stop ? nil : newValue.rawValue }
    }

    var insistence: InsistencePlan {
        get {
            InsistencePlan(
                intervalMinutes: insistenceIntervalMinutes,
                repeats: insistenceRepeats
            )
        }
        set {
            insistenceIntervalMinutes = newValue.intervalMinutes
            insistenceRepeats = newValue.repeats
        }
    }

    var followUpAlarmIDs: [UUID] {
        get {
            followUpAlarmIDsRaw
                .split(separator: ",")
                .compactMap { entry in
                    UUID(uuidString: String(entry.prefix { $0 != "@" }))
                }
        }
        set {
            followUpAlarmIDsRaw = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    /// Las vueltas registradas, con la mañana a la que pertenecen.
    ///
    /// Cada entrada es `uuid@ocurrencia@disparo`, con las fechas en segundos
    /// desde 1970. Sigue siendo una cadena separada por comas, así que no hace
    /// falta otra versión del esquema. Una entrada sin fechas —el formato de
    /// antes, solo el identificador— se lee como ya pasada: lo prudente con una
    /// vuelta de la que no se sabe cuándo suena es cancelarla en la próxima
    /// limpieza, no conservarla.
    var scheduledFollowUps: [ScheduledFollowUp] {
        get {
            followUpAlarmIDsRaw.split(separator: ",").compactMap { entry in
                let parts = entry.split(separator: "@")
                guard let id = parts.first.flatMap({ UUID(uuidString: String($0)) }) else {
                    return nil
                }
                guard parts.count == 3,
                      let occurrence = TimeInterval(parts[1]),
                      let fire = TimeInterval(parts[2])
                else {
                    return ScheduledFollowUp(systemID: id, occurrence: .distantPast, fireDate: .distantPast)
                }
                return ScheduledFollowUp(
                    systemID: id,
                    occurrence: Date(timeIntervalSince1970: occurrence),
                    fireDate: Date(timeIntervalSince1970: fire)
                )
            }
        }
        set {
            followUpAlarmIDsRaw = newValue.map { entry in
                let occurrence = Int(entry.occurrence.timeIntervalSince1970)
                let fire = Int(entry.fireDate.timeIntervalSince1970)
                return "\(entry.systemID.uuidString)@\(occurrence)@\(fire)"
            }
            .joined(separator: ",")
        }
    }

    /// La mañana que está sonando ahora y aún espera que se desarme, si la hay.
    ///
    /// Empieza cuando suena la alarma principal y dura hasta un minuto después
    /// de la última vuelta. Antes de esa hora no hay nada que desarmar: abrir la
    /// app a las 6:55 no debe enseñar la pantalla de desarme de las 7:00.
    func occurrenceAwaitingDisarm(at now: Date) -> Date? {
        guard requiresDisarm else { return nil }
        return scheduledFollowUps
            .filter { $0.occurrence <= now && $0.fireDate.addingTimeInterval(60) >= now }
            .map(\.occurrence)
            .min()
    }

    /// Las vueltas que le tocan a esta alarma según su plan.
    var followUps: [FollowUpAlarm] {
        InsistenceCalculator.followUps(
            after: minuteOfDay,
            schedule: schedule,
            plan: insistence
        )
    }

    /// Si esta alarma pide algo más que pulsar Parar.
    ///
    /// Insistir sin método de desarme sería una alarma que vuelve y no hay forma
    /// de callar del todo, así que las dos cosas van juntas.
    var requiresDisarm: Bool {
        disarmMethod.requiresAction && insistence.isActive
    }
}

// MARK: - Presentación

extension AlarmItem {
    /// «7:30». El formato vive en `ClockTime`, compartido con las tareas y con
    /// la sección de ciclos de sueño.
    var timeText: String {
        ClockTime.text(minuteOfDay: minuteOfDay)
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

// MARK: - Próxima alarma

extension AlarmItem {
    /// La primera alarma de la lista que va a sonar a partir de `now`.
    ///
    /// Es función pura para poder alimentarla desde un `@Query` de la vista en
    /// lugar de consultar la base en cada redibujado, y para poder probarla con
    /// una fecha fija.
    ///
    /// Recorre los siete próximos días en lugar de resolverlo con aritmética
    /// modular: son siete iteraciones y el código se lee sin tener que confiar
    /// en él.
    static func next(
        from alarms: [AlarmItem],
        now: Date = .now,
        calendar: Calendar = AppCalendar.current
    ) -> AlarmItem? {
        var candidates: [AlarmItem] = []
        for alarm in alarms where alarm.isSchedulable {
            candidates.append(alarm)
        }
        guard !candidates.isEmpty else { return nil }

        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let todayWeekday = calendar.component(.weekday, from: now)

        for dayOffset in 0..<7 {
            let weekday = (todayWeekday - 1 + dayOffset) % 7 + 1

            var onThatDay: [AlarmItem] = []
            for alarm in candidates where alarm.schedule.contains(weekday: weekday) {
                // Hoy solo cuentan las que aún no han sonado.
                if dayOffset > 0 || alarm.minuteOfDay > nowMinute {
                    onThatDay.append(alarm)
                }
            }

            if let earliest = onThatDay.min(by: { $0.minuteOfDay < $1.minuteOfDay }) {
                return earliest
            }
        }

        return nil
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
