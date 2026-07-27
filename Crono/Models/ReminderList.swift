import Foundation
import SwiftData

/// Una lista de tareas: «Casa», «Trabajo», «Compra».
///
/// Se llama `ReminderList` y no `TaskList` para no chocar de nombre con el
/// `Task` de la concurrencia de Swift, que aparece en cualquier archivo con
/// `async`.
@Model
final class ReminderList {
    @Attribute(.unique) var uuid: UUID

    var name: String

    /// `HabitColor.rawValue`. Se reutiliza la misma paleta cerrada que los
    /// hábitos: son dos funciones independientes, pero el usuario no querría dos
    /// juegos de colores distintos en la misma app.
    var colorRaw: String

    /// Símbolo de SF Symbols que identifica la lista, como en Recordatorios.
    var symbolName: String

    var createdAt: Date

    /// Posición en la lista de listas, controlada por el usuario.
    var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \Reminder.list)
    var reminders: [Reminder]

    init(
        uuid: UUID = UUID(),
        name: String,
        color: HabitColor = .default,
        symbolName: String = "list.bullet",
        createdAt: Date = .now,
        sortIndex: Int = 0
    ) {
        self.uuid = uuid
        self.name = name
        self.colorRaw = color.rawValue
        self.symbolName = symbolName
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.reminders = []
    }
}

// MARK: - Acceso tipado

extension ReminderList {
    var color: HabitColor {
        get { HabitColor(rawValue: colorRaw) ?? .default }
        set { colorRaw = newValue.rawValue }
    }
}

// MARK: - Consulta

extension ReminderList {
    /// Tareas pendientes de nivel superior, sin contar subtareas.
    ///
    /// Las subtareas se dibujan dentro de su tarea madre, así que contarlas en el
    /// total de la lista daría una cifra que no se corresponde con lo que se ve.
    var pendingCount: Int {
        var count = 0
        for reminder in reminders where !reminder.isCompleted && reminder.parent == nil {
            count += 1
        }
        return count
    }
}
