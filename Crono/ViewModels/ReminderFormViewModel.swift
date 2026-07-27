import Foundation
import Observation

/// Borrador editable de una tarea.
///
/// Igual que `HabitFormViewModel`: nada se escribe en la base hasta pulsar
/// Guardar, así que Cancelar no tiene nada que deshacer.
@MainActor
@Observable
final class ReminderFormViewModel {
    private let store: ReminderStore
    private let calendar: Calendar

    let editingReminder: Reminder?
    private let targetList: ReminderList?

    // MARK: - Borrador

    var title: String
    var notes: String
    var priority: ReminderPriority
    var isFlagged: Bool

    /// Fecha de vencimiento como `Date`, que es lo que consumen los
    /// `DatePicker`. Se convierte a `DayKey` y minutos al guardar.
    var hasDueDate: Bool
    var dueDate: Date

    var hasDueTime: Bool

    var repeats: Bool
    var recurrence: RecurrenceRule

    init(store: ReminderStore, mode: Mode, calendar: Calendar = AppCalendar.current) {
        self.store = store
        self.calendar = calendar

        switch mode {
        case let .create(list):
            self.editingReminder = nil
            self.targetList = list
            self.title = ""
            self.notes = ""
            self.priority = .none
            self.isFlagged = false
            self.hasDueDate = false
            self.dueDate = calendar.startOfDay(for: .now)
            self.hasDueTime = false
            self.repeats = false
            self.recurrence = .daily

        case let .edit(reminder):
            self.editingReminder = reminder
            self.targetList = reminder.list
            self.title = reminder.title
            self.notes = reminder.notes
            self.priority = reminder.priority
            self.isFlagged = reminder.isFlagged
            self.hasDueDate = reminder.dueDayKey != nil
            self.dueDate = reminder.dueDate(calendar: calendar) ?? calendar.startOfDay(for: .now)
            self.hasDueTime = reminder.dueMinuteOfDay != nil
            self.repeats = reminder.recurrence != nil
            self.recurrence = reminder.recurrence ?? .daily
        }
    }

    enum Mode {
        case create(ReminderList)
        case edit(Reminder)
    }

    // MARK: - Presentación

    var navigationTitle: String {
        editingReminder == nil ? "Nueva tarea" : "Editar tarea"
    }

    var isEditing: Bool { editingReminder != nil }

    var listName: String { targetList?.name ?? "Sin lista" }

    // MARK: - Validación

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool { !trimmedTitle.isEmpty }

    /// La repetición sin fecha no tiene sentido: no habría desde cuándo contar.
    var repeatRequiresDate: Bool { repeats && !hasDueDate }

    var validationMessage: String? {
        if repeatRequiresDate { return "Una tarea que se repite necesita una fecha de vencimiento." }
        if !title.isEmpty && trimmedTitle.isEmpty { return "El título no puede ser solo espacios." }
        return nil
    }

    // MARK: - Guardar

    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }

        let dayKey: DayKey? = hasDueDate ? calendar.dayKey(from: dueDate) : nil
        let minute: Int? = (hasDueDate && hasDueTime) ? minuteOfDay(from: dueDate) : nil
        // Sin fecha no se guarda repetición, aunque el conmutador esté puesto.
        let rule: RecurrenceRule? = (repeats && hasDueDate) ? recurrence : nil

        if let editingReminder {
            store.update(
                editingReminder,
                title: trimmedTitle,
                notes: notes,
                dueDayKey: dayKey,
                dueMinuteOfDay: minute,
                priority: priority,
                isFlagged: isFlagged,
                recurrence: rule,
                list: nil
            )
            return store.failure == nil
        }

        guard let targetList else { return false }
        return store.createReminder(
            title: trimmedTitle,
            in: targetList,
            notes: notes,
            dueDayKey: dayKey,
            dueMinuteOfDay: minute,
            priority: priority,
            isFlagged: isFlagged,
            recurrence: rule
        ) != nil
    }

    func delete() {
        guard let editingReminder else { return }
        store.delete(editingReminder)
    }

    // MARK: - Internos

    private func minuteOfDay(from date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
