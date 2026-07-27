import Foundation
import SwiftData

/// Un hábito que el usuario quiere seguir.
///
/// Los atributos persistidos son tipos primitivos (`String`, `Int`, `Date`) y los
/// tipos ricos —`HabitColor`, `WeekdaySet`— se exponen mediante propiedades
/// calculadas sobre ellos. Así el esquema de SwiftData permanece estable aunque
/// esos enums crezcan, y no hace falta migración al añadir un color nuevo.
@Model
final class Habit {
    /// Identidad estable, independiente del `PersistentIdentifier` de SwiftData.
    /// Sirve para referenciar el hábito desde la UI sin arrastrar el objeto.
    @Attribute(.unique) var uuid: UUID

    var name: String

    /// Descripción opcional. Se guarda `""` en lugar de `nil` para que la UI y las
    /// consultas no tengan que distinguir entre "vacía" y "ausente".
    var notes: String

    /// `HabitColor.rawValue`. Usar `color` en su lugar.
    var colorRaw: String

    /// `WeekdaySet.rawValue`. Usar `schedule` en su lugar.
    var scheduledWeekdaysMask: Int

    /// Momento de creación. Acota el cálculo de la mejor racha: los días
    /// anteriores a esta fecha no cuentan como fallos.
    var createdAt: Date

    /// `nil` mientras el hábito está activo.
    ///
    /// Archivar en lugar de borrar preserva el historial: el usuario puede dejar
    /// un hábito sin perder las rachas que ya consiguió. El borrado real existe
    /// aparte y sí elimina los registros en cascada.
    var archivedAt: Date?

    /// Posición en la lista, controlada por el usuario.
    var sortIndex: Int

    /// Días en los que se marcó como completado. La existencia de un registro
    /// *es* la compleción; no hay registros con valor "false".
    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    var completions: [HabitCompletion]

    init(
        uuid: UUID = UUID(),
        name: String,
        notes: String = "",
        color: HabitColor = .default,
        schedule: WeekdaySet = .everyDay,
        createdAt: Date = .now,
        archivedAt: Date? = nil,
        sortIndex: Int = 0
    ) {
        self.uuid = uuid
        self.name = name
        self.notes = notes
        self.colorRaw = color.rawValue
        self.scheduledWeekdaysMask = schedule.rawValue
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.sortIndex = sortIndex
        self.completions = []
    }
}

// MARK: - Acceso tipado a los atributos persistidos

extension Habit {
    /// Color del hábito. Cae en el color por defecto si el dato almacenado no
    /// corresponde a ningún caso conocido (por ejemplo tras una regresión de
    /// versión), en lugar de fallar.
    var color: HabitColor {
        get { HabitColor(rawValue: colorRaw) ?? .default }
        set { colorRaw = newValue.rawValue }
    }

    /// Días de la semana en los que el hábito está programado.
    var schedule: WeekdaySet {
        get { WeekdaySet(rawValue: scheduledWeekdaysMask) }
        set { scheduledWeekdaysMask = newValue.rawValue }
    }
}

// MARK: - Estado

extension Habit {
    var isActive: Bool { archivedAt == nil }

    var isDaily: Bool { schedule.isEveryDay }

    /// Primer día en el que el hábito pudo cumplirse.
    var createdDayKey: DayKey { createdAt.dayKey }
}

// MARK: - Programación

extension Habit {
    /// Indica si el hábito toca en un día de la semana (`Calendar.weekday`, 1…7).
    func isScheduled(onWeekday weekday: Int) -> Bool {
        schedule.contains(weekday: weekday)
    }

    /// Indica si el hábito toca en un día concreto.
    ///
    /// Devuelve `false` para días anteriores a la creación del hábito: no tiene
    /// sentido exigir un hábito que aún no existía.
    func isScheduled(on dayKey: DayKey, calendar: Calendar = AppCalendar.current) -> Bool {
        guard dayKey >= createdDayKey,
              let weekday = calendar.weekday(fromDayKey: dayKey)
        else { return false }
        return isScheduled(onWeekday: weekday)
    }
}

// MARK: - Compleciones

extension Habit {
    /// Días completados, como conjunto para consultas en tiempo constante.
    ///
    /// Materializa la relación, así que conviene calcularlo una vez por pantalla
    /// y no dentro de un bucle de dibujado.
    ///
    /// Se rellena con un bucle en lugar de `Set(completions.map(\.dayKey))`: ese
    /// encadenado —un `map` por key path alimentando el inicializador genérico
    /// de `Set`, sobre una relación cuyo tipo resuelve el macro `@Model`— hacía
    /// que el inferidor de tipos de Swift se rindiera al compilar este archivo.
    var completedDayKeys: Set<DayKey> {
        var keys: Set<DayKey> = []
        for completion in completions {
            keys.insert(completion.dayKey)
        }
        return keys
    }

    func isCompleted(on dayKey: DayKey) -> Bool {
        for completion in completions where completion.dayKey == dayKey {
            return true
        }
        return false
    }

    /// El registro de compleción de un día, si existe.
    func completion(on dayKey: DayKey) -> HabitCompletion? {
        for completion in completions where completion.dayKey == dayKey {
            return completion
        }
        return nil
    }
}
