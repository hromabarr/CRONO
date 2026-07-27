import Foundation
import SwiftData

/// Una tarea.
///
/// El vencimiento se guarda en dos campos separados, igual que hace
/// Recordatorios: `dueDayKey` dice **qué día** y `dueMinuteOfDay` dice **a qué
/// hora**, y este último puede ser `nil`. Esa separación es la que distingue
/// «el martes» de «el martes a las 10:00», y es justo la diferencia entre una
/// tarea que solo aparece en su día y una que además avisa.
///
/// `dueDayKey` es el mismo `DayKey` (`yyyyMMdd`) que usan los hábitos, por la
/// misma razón: un vencimiento es un día de calendario, no un instante, y no
/// debe desplazarse si el usuario cambia de zona horaria.
@Model
final class Reminder {
    @Attribute(.unique) var uuid: UUID

    var title: String

    /// Nota larga opcional. `""` en lugar de `nil` para no distinguir entre
    /// "vacía" y "ausente" en cada consulta.
    var notes: String

    var isCompleted: Bool

    /// Cuándo se marcó. Sirve para «completadas hoy» y para poder deshacer.
    var completedAt: Date?

    var createdAt: Date

    /// Orden manual dentro de su lista.
    var sortIndex: Int

    // MARK: - Vencimiento

    /// Día de vencimiento, o `nil` si la tarea no tiene fecha.
    var dueDayKey: DayKey?

    /// Minutos desde medianoche (0…1439), o `nil` si es de todo el día.
    ///
    /// Solo las tareas con hora generan notificación: sin hora no hay momento al
    /// que avisar.
    var dueMinuteOfDay: Int?

    // MARK: - Marcas

    /// `ReminderPriority.rawValue`. Usar `priority`.
    var priorityRaw: Int

    var isFlagged: Bool

    /// `RecurrenceRule.rawValue`, o `nil` si no se repite. Usar `recurrence`.
    var recurrenceRaw: String?

    // MARK: - Relaciones

    var list: ReminderList?

    /// Subtareas. Relación consigo misma: una tarea puede contener otras.
    @Relationship(deleteRule: .cascade, inverse: \Reminder.parent)
    var subtasks: [Reminder]

    /// Tarea madre, o `nil` si es de nivel superior.
    var parent: Reminder?

    init(
        uuid: UUID = UUID(),
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        sortIndex: Int = 0,
        dueDayKey: DayKey? = nil,
        dueMinuteOfDay: Int? = nil,
        priority: ReminderPriority = .none,
        isFlagged: Bool = false,
        recurrence: RecurrenceRule? = nil
    ) {
        self.uuid = uuid
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.dueDayKey = dueDayKey
        self.dueMinuteOfDay = dueMinuteOfDay
        self.priorityRaw = priority.rawValue
        self.isFlagged = isFlagged
        self.recurrenceRaw = recurrence?.rawValue
        self.subtasks = []
    }
}

// MARK: - Acceso tipado

extension Reminder {
    var priority: ReminderPriority {
        get { ReminderPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var recurrence: RecurrenceRule? {
        get {
            guard let recurrenceRaw else { return nil }
            return RecurrenceRule(rawValue: recurrenceRaw)
        }
        set { recurrenceRaw = newValue?.rawValue }
    }
}

// MARK: - Vencimiento

extension Reminder {
    var hasDueDate: Bool { dueDayKey != nil }

    /// Tiene hora concreta, así que puede generar un aviso.
    var hasDueTime: Bool { dueDayKey != nil && dueMinuteOfDay != nil }

    /// Instante exacto del vencimiento, para programar la notificación.
    ///
    /// `nil` si no hay fecha. Sin hora se toma el inicio del día: es lo que hace
    /// Recordatorios con las tareas de todo el día.
    func dueDate(calendar: Calendar = AppCalendar.current) -> Date? {
        guard let dueDayKey, let day = calendar.date(fromDayKey: dueDayKey) else { return nil }
        guard let dueMinuteOfDay else { return day }
        return calendar.date(byAdding: .minute, value: dueMinuteOfDay, to: day)
    }

    /// Vencida: tenía fecha, ya pasó y sigue sin hacerse.
    func isOverdue(today: DayKey, nowMinuteOfDay: Int) -> Bool {
        guard !isCompleted, let dueDayKey else { return false }
        if dueDayKey < today { return true }
        guard dueDayKey == today, let dueMinuteOfDay else { return false }
        return dueMinuteOfDay < nowMinuteOfDay
    }

    func isDue(on dayKey: DayKey) -> Bool {
        dueDayKey == dayKey
    }
}

// MARK: - Jerarquía

extension Reminder {
    var isTopLevel: Bool { parent == nil }

    /// Subtareas hechas frente al total, para el indicador «2 de 5».
    ///
    /// Tipo con nombre y no una tupla `(completed:total:)`: esto se lee dentro de
    /// una fila, o sea dentro de un `ViewBuilder`, y las tuplas con etiquetas
    /// atravesando un builder ya hicieron que el compilador se rindiera una vez
    /// en este proyecto.
    struct SubtaskProgress: Equatable, Sendable {
        var completed: Int
        var total: Int

        var isEmpty: Bool { total == 0 }
        var isComplete: Bool { total > 0 && completed == total }
        var text: String { "\(completed) de \(total)" }
    }

    var subtaskProgress: SubtaskProgress {
        var completed = 0
        for subtask in subtasks where subtask.isCompleted {
            completed += 1
        }
        return SubtaskProgress(completed: completed, total: subtasks.count)
    }
}
