import Foundation
import SwiftData

/// Único punto de escritura sobre las tareas.
///
/// Mismo contrato que `HabitStore`: las vistas leen con `@Query` y nunca escriben
/// en el `ModelContext`. `@MainActor` porque `ModelContext` no es `Sendable`.
/// Reutiliza `StoreFailure` para que los errores lleguen al usuario con el mismo
/// formato que los de hábitos.
@MainActor
@Observable
final class ReminderStore {
    private let context: ModelContext

    var failure: StoreFailure?

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Listas

    /// Nombre de la lista que se crea sola la primera vez.
    static let defaultListName = "Recordatorios"

    /// Garantiza que exista al menos una lista.
    ///
    /// Sin ella, un usuario recién instalado no tendría dónde poner su primera
    /// tarea y la pantalla sería un callejón sin salida.
    @discardableResult
    func ensureDefaultList() -> ReminderList? {
        let existing = allLists()
        if let first = existing.first { return first }

        return createList(name: Self.defaultListName, color: .blue, symbolName: "list.bullet")
    }

    @discardableResult
    func createList(
        name: String,
        color: HabitColor = .default,
        symbolName: String = "list.bullet"
    ) -> ReminderList? {
        let list = ReminderList(
            name: name.trimmedForStorage,
            color: color,
            symbolName: symbolName,
            sortIndex: nextListSortIndex()
        )
        context.insert(list)

        guard save(action: "crear la lista") else {
            context.rollback()
            return nil
        }
        return list
    }

    func update(_ list: ReminderList, name: String, color: HabitColor, symbolName: String) {
        list.name = name.trimmedForStorage
        list.color = color
        list.symbolName = symbolName

        if !save(action: "guardar la lista") { context.rollback() }
    }

    /// Borra la lista y, en cascada, sus tareas. Irreversible.
    func delete(_ list: ReminderList) {
        context.delete(list)
        if !save(action: "eliminar la lista") { context.rollback() }
    }

    func moveLists(_ lists: [ReminderList], from source: IndexSet, to destination: Int) {
        let reordered = lists.reordered(from: source, to: destination)
        for (index, list) in reordered.enumerated() {
            list.sortIndex = index
        }
        if !save(action: "reordenar las listas") { context.rollback() }
    }

    // MARK: - Tareas

    @discardableResult
    func createReminder(
        title: String,
        in list: ReminderList,
        notes: String = "",
        dueDayKey: DayKey? = nil,
        dueMinuteOfDay: Int? = nil,
        priority: ReminderPriority = .none,
        isFlagged: Bool = false,
        recurrence: RecurrenceRule? = nil,
        parent: Reminder? = nil
    ) -> Reminder? {
        // Una hora sin día no significa nada: se descarta en lugar de guardar un
        // estado que la interfaz no sabría representar.
        let minute = dueDayKey == nil ? nil : dueMinuteOfDay

        let reminder = Reminder(
            title: title.trimmedForStorage,
            notes: notes.trimmedForStorage,
            sortIndex: nextReminderSortIndex(in: list),
            dueDayKey: dueDayKey,
            dueMinuteOfDay: minute,
            priority: priority,
            isFlagged: isFlagged,
            recurrence: recurrence
        )

        context.insert(reminder)
        reminder.list = list
        reminder.parent = parent

        guard save(action: "crear la tarea") else {
            context.rollback()
            return nil
        }
        return reminder
    }

    func update(
        _ reminder: Reminder,
        title: String,
        notes: String,
        dueDayKey: DayKey?,
        dueMinuteOfDay: Int?,
        priority: ReminderPriority,
        isFlagged: Bool,
        recurrence: RecurrenceRule?,
        list: ReminderList?
    ) {
        reminder.title = title.trimmedForStorage
        reminder.notes = notes.trimmedForStorage
        reminder.dueDayKey = dueDayKey
        reminder.dueMinuteOfDay = dueDayKey == nil ? nil : dueMinuteOfDay
        reminder.priority = priority
        reminder.isFlagged = isFlagged
        reminder.recurrence = recurrence
        if let list { reminder.list = list }

        if !save(action: "guardar la tarea") { context.rollback() }
    }

    func delete(_ reminder: Reminder) {
        context.delete(reminder)
        if !save(action: "eliminar la tarea") { context.rollback() }
    }

    func moveReminders(_ reminders: [Reminder], from source: IndexSet, to destination: Int) {
        let reordered = reminders.reordered(from: source, to: destination)
        for (index, reminder) in reordered.enumerated() {
            reminder.sortIndex = index
        }
        if !save(action: "reordenar las tareas") { context.rollback() }
    }

    // MARK: - Completar

    /// Marca o desmarca una tarea.
    ///
    /// Al completar una tarea madre se completan también sus subtareas, que es
    /// lo que hace Recordatorios: dejar subtareas pendientes bajo una tarea hecha
    /// sería un estado que el usuario no puede interpretar.
    ///
    /// Desmarcar **no** desmarca las subtareas: si estaban hechas, lo estaban.
    func toggleCompletion(for reminder: Reminder, at date: Date = .now) {
        let completing = !reminder.isCompleted

        reminder.isCompleted = completing
        reminder.completedAt = completing ? date : nil

        if completing {
            for subtask in reminder.subtasks where !subtask.isCompleted {
                subtask.isCompleted = true
                subtask.completedAt = date
            }
        }

        if !save(action: "guardar la tarea") { context.rollback() }
    }

    /// Borra de golpe las tareas completadas de una lista.
    func clearCompleted(in list: ReminderList) {
        for reminder in list.reminders where reminder.isCompleted {
            context.delete(reminder)
        }
        if !save(action: "borrar las tareas completadas") { context.rollback() }
    }

    // MARK: - Consultas

    func allLists() -> [ReminderList] {
        fetch(ReminderQueries.lists, action: "cargar las listas")
    }

    func pendingReminders() -> [Reminder] {
        fetch(ReminderQueries.pending, action: "cargar las tareas")
    }

    // MARK: - Internos

    private func fetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        action: String
    ) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            failure = StoreFailure(action: action, reason: error.localizedDescription)
            return []
        }
    }

    private func nextListSortIndex() -> Int {
        var descriptor = FetchDescriptor<ReminderList>(
            sortBy: [SortDescriptor(\ReminderList.sortIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor))?.first?.sortIndex ?? -1) + 1
    }

    private func nextReminderSortIndex(in list: ReminderList) -> Int {
        var highest = -1
        for reminder in list.reminders where reminder.sortIndex > highest {
            highest = reminder.sortIndex
        }
        return highest + 1
    }

    private func save(action: String) -> Bool {
        guard context.hasChanges else { return true }

        do {
            try context.save()
            return true
        } catch {
            failure = StoreFailure(action: action, reason: error.localizedDescription)
            return false
        }
    }
}

// MARK: - Auxiliares

private extension String {
    var trimmedForStorage: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
