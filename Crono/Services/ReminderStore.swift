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
    private let notifier: any ReminderNotifying
    private let calendar: Calendar

    var failure: StoreFailure?

    /// Último estado conocido del permiso de notificaciones.
    private(set) var notificationAuthorization: AlarmAuthorization = .notDetermined

    init(
        context: ModelContext,
        notifier: any ReminderNotifying = NoopReminderNotifier(),
        calendar: Calendar = AppCalendar.current
    ) {
        self.context = context
        self.notifier = notifier
        self.calendar = calendar
    }

    // MARK: - Permiso de avisos

    @discardableResult
    func requestNotificationAuthorization() async -> AlarmAuthorization {
        let state = await notifier.requestAuthorization()
        notificationAuthorization = state
        return state
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorization = await notifier.authorization
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

        Task { await syncNotification(for: reminder) }
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

        guard save(action: "guardar la tarea") else {
            context.rollback()
            return
        }

        Task { await syncNotification(for: reminder) }
    }

    func delete(_ reminder: Reminder) {
        // Los identificadores se anotan antes de borrar: después ya no habría de
        // dónde leerlos, y quedaría un aviso programado por algo que el usuario
        // cree eliminado.
        var ids = [reminder.uuid]
        for subtask in reminder.subtasks {
            ids.append(subtask.uuid)
        }

        context.delete(reminder)
        if !save(action: "eliminar la tarea") { context.rollback() }

        Task {
            for id in ids {
                await notifier.cancel(reminderID: id)
            }
        }
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

        let successor = completing ? makeNextOccurrence(of: reminder) : nil

        guard save(action: "guardar la tarea") else {
            context.rollback()
            return
        }

        Task {
            // Una tarea completada no tiene que avisar de nada.
            if completing {
                await notifier.cancel(reminderID: reminder.uuid)
            } else {
                await syncNotification(for: reminder)
            }
            if let successor {
                await syncNotification(for: successor)
            }
        }
    }

    // MARK: - Repetición

    /// Crea la siguiente aparición de una tarea recurrente al completarla.
    ///
    /// La completada se queda completada y nace una nueva con el vencimiento
    /// siguiente. Es lo que hace Recordatorios, y preserva el historial: mover la
    /// fecha de la misma tarea borraría cualquier rastro de que se cumplió.
    ///
    /// Devuelve `nil` si la tarea no se repite, si no tiene fecha —una repetición
    /// sin vencimiento no tiene desde dónde contar— o si es una subtarea: quien
    /// se repite es la madre, y duplicar las hijas por su cuenta las dejaría
    /// huérfanas.
    @discardableResult
    private func makeNextOccurrence(of reminder: Reminder) -> Reminder? {
        guard reminder.parent == nil,
              let rule = reminder.recurrence,
              let dueDayKey = reminder.dueDayKey,
              let list = reminder.list,
              let nextDayKey = rule.nextDueDayKey(after: dueDayKey, calendar: calendar)
        else { return nil }

        let next = Reminder(
            title: reminder.title,
            notes: reminder.notes,
            sortIndex: reminder.sortIndex,
            dueDayKey: nextDayKey,
            dueMinuteOfDay: reminder.dueMinuteOfDay,
            priority: reminder.priority,
            isFlagged: reminder.isFlagged,
            recurrence: rule
        )
        context.insert(next)
        next.list = list

        // Las subtareas se copian sin marcar: una lista de comprobación semanal
        // que reapareciera ya completada no serviría de nada.
        let steps = reminder.subtasks.sorted { $0.sortIndex < $1.sortIndex }
        for subtask in steps {
            let copy = Reminder(
                title: subtask.title,
                notes: subtask.notes,
                sortIndex: subtask.sortIndex
            )
            context.insert(copy)
            copy.list = list
            copy.parent = next
        }

        return next
    }

    // MARK: - Avisos

    /// Deja el aviso del sistema acorde con la tarea.
    ///
    /// Solo avisan las tareas con **hora**: sin ella no hay momento al que
    /// avisar, y disparar a medianoche sería inventarse uno.
    private func syncNotification(for reminder: Reminder) async {
        await notifier.cancel(reminderID: reminder.uuid)

        guard let request = notificationRequest(for: reminder) else { return }

        await refreshNotificationAuthorization()
        guard notificationAuthorization == .authorized else { return }

        await notifier.schedule(request)
    }

    /// Qué aviso le corresponde a una tarea, o `nil` si no le corresponde
    /// ninguno.
    ///
    /// La decisión está separada del envío porque el envío ocurre en un `Task`
    /// suelto —las notificaciones son de mejor esfuerzo y no deben bloquear una
    /// escritura— y eso no se puede probar sin depender del reloj. Esto sí.
    func notificationRequest(for reminder: Reminder) -> ReminderNotificationRequest? {
        // Solo avisan las tareas con **hora**: sin ella no hay momento al que
        // avisar, y disparar a medianoche sería inventarse uno.
        guard !reminder.isCompleted,
              reminder.hasDueTime,
              let fireDate = reminder.dueDate(calendar: calendar)
        else { return nil }

        return ReminderNotificationRequest(
            reminderID: reminder.uuid,
            title: reminder.title,
            body: reminder.list?.name ?? "",
            fireDate: fireDate
        )
    }

    /// Borra de golpe las tareas completadas de una lista.
    func clearCompleted(in list: ReminderList) {
        var ids: [UUID] = []
        for reminder in list.reminders where reminder.isCompleted {
            ids.append(reminder.uuid)
            context.delete(reminder)
        }
        if !save(action: "borrar las tareas completadas") { context.rollback() }

        Task {
            for id in ids {
                await notifier.cancel(reminderID: id)
            }
        }
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
