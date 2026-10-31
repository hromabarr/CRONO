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

    /// Nil in migrated V1 records; interpreted as «Durante el día».
    var routineRaw: String?

    /// Cuánto hay que hacer al día para darlo por cumplido. 1 es un hábito de
    /// sí o no, el de siempre; más de 1 es «8 vasos de agua».
    ///
    /// Con valor por defecto en la declaración para que la migración ligera
    /// rellene los hábitos que ya existían.
    var targetCount: Int = 1

    /// La unidad del objetivo, en plural: «vasos», «páginas», «min». `""` si no
    /// tiene.
    var unit: String = ""

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
        sortIndex: Int = 0,
        routine: HabitRoutine = .anytime,
        targetCount: Int = 1,
        unit: String = ""
    ) {
        self.uuid = uuid
        self.name = name
        self.notes = notes
        self.colorRaw = color.rawValue
        self.scheduledWeekdaysMask = schedule.rawValue
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.sortIndex = sortIndex
        self.routineRaw = routine.rawValue
        self.targetCount = Habit.clampedTarget(targetCount)
        self.unit = unit
        self.completions = []
    }
}

// MARK: - Acceso tipado a los atributos persistidos

extension Habit {
    var routine: HabitRoutine {
        get { routineRaw.flatMap(HabitRoutine.init(rawValue:)) ?? .anytime }
        set { routineRaw = newValue.rawValue }
    }

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
        if let archivedAt, dayKey > calendar.dayKey(from: archivedAt) { return false }
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
    ///
    /// Solo cuentan los días en que se llegó al objetivo: tres vasos de ocho no
    /// son un día cumplido. Así las rachas, las rutinas y el historial siguen
    /// funcionando sin saber que existen los hábitos con cantidad.
    var completedDayKeys: Set<DayKey> {
        var keys: Set<DayKey> = []
        for completion in completions where completion.count >= targetCount {
            keys.insert(completion.dayKey)
        }
        return keys
    }

    func isCompleted(on dayKey: DayKey) -> Bool {
        count(on: dayKey) >= targetCount
    }

    /// Cuánto se hizo ese día. 0 si no hay registro.
    func count(on dayKey: DayKey) -> Int {
        completion(on: dayKey)?.count ?? 0
    }

    /// El registro de compleción de un día, si existe.
    func completion(on dayKey: DayKey) -> HabitCompletion? {
        for completion in completions where completion.dayKey == dayKey {
            return completion
        }
        return nil
    }
}

// MARK: - Objetivo

extension Habit {
    /// Tope del objetivo diario. Más que esto no es un hábito, es un contador.
    static let maxTarget = 99

    /// Tope de lo que se puede apuntar en un día. Pasarse del objetivo vale
    /// —nueve vasos de ocho—, pero no sin límite: un dedo apoyado no debe
    /// llenar la base de números absurdos.
    static let maxDailyCount = 999

    static func clampedTarget(_ value: Int) -> Int {
        max(1, min(value, maxTarget))
    }

    /// Si se mide en cantidad y no con un sí o un no.
    var hasQuantityGoal: Bool { targetCount > 1 }

    /// «3 de 8 vasos», o «3 de 8» sin unidad.
    func progressText(on dayKey: DayKey) -> String {
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "\(count(on: dayKey)) de \(targetCount)"
        return trimmed.isEmpty ? base : "\(base) \(trimmed)"
    }

    /// Fracción del objetivo cumplida ese día, entre 0 y 1.
    func fraction(on dayKey: DayKey) -> Double {
        min(1, Double(count(on: dayKey)) / Double(max(1, targetCount)))
    }
}
