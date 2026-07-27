import Foundation
import Observation

/// Borrador editable de un hábito, para crear y para editar.
///
/// Las dos operaciones usan la misma pantalla porque son el mismo formulario con
/// distinto punto de partida. Mantener el borrador aquí, y no en el `@Model`,
/// evita escribir en la base de datos con cada tecla: hasta que se pulsa Guardar
/// no se toca nada persistido, así que Cancelar no necesita deshacer nada.
@MainActor
@Observable
final class HabitFormViewModel {
    enum Mode: Equatable {
        case create
        case edit(Habit)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create): true
            case let (.edit(a), .edit(b)): a.id == b.id
            default: false
            }
        }
    }

    let mode: Mode
    private let store: HabitStore

    // MARK: - Borrador

    var name: String
    var notes: String
    var color: HabitColor
    var schedule: WeekdaySet

    init(mode: Mode, store: HabitStore) {
        self.mode = mode
        self.store = store

        switch mode {
        case .create:
            self.name = ""
            self.notes = ""
            self.color = .default
            self.schedule = .everyDay
        case let .edit(habit):
            self.name = habit.name
            self.notes = habit.notes
            self.color = habit.color
            self.schedule = habit.schedule
        }
    }

    // MARK: - Presentación

    var navigationTitle: String {
        switch mode {
        case .create: "Nuevo hábito"
        case .edit: "Editar hábito"
        }
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// El hábito que se está editando, si lo hay.
    var editingHabit: Habit? {
        if case let .edit(habit) = mode { return habit }
        return nil
    }

    // MARK: - Programación

    var isEveryDay: Bool { schedule.isEveryDay }

    func toggle(weekday: Int) {
        schedule = schedule.toggling(weekday: weekday)
    }

    func isSelected(weekday: Int) -> Bool {
        schedule.contains(weekday: weekday)
    }

    /// «Todos los días» no es un modo aparte: activa o vacía los siete días.
    /// Es la misma máscara, con los siete bits puestos.
    func setEveryDay(_ enabled: Bool) {
        schedule = enabled ? .everyDay : []
    }

    var scheduleSummary: String { schedule.displayDescription }

    // MARK: - Validación

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isNameValid: Bool { !trimmedName.isEmpty }

    var isScheduleValid: Bool { !schedule.isEmpty }

    var canSave: Bool { isNameValid && isScheduleValid }

    /// Mensaje de validación en línea, no al pulsar Guardar: el usuario se
    /// entera del problema mientras lo está causando.
    ///
    /// Solo se queja del nombre cuando el campo ya se tocó, para no recibir al
    /// usuario con un error en un formulario que aún no ha rellenado.
    var validationMessage: String? {
        if !isScheduleValid { return "Elige al menos un día." }
        if !name.isEmpty && !isNameValid { return "El nombre no puede ser solo espacios." }
        return nil
    }

    // MARK: - Acciones

    /// Persiste el borrador. Devuelve `false` si no era válido o si falló el
    /// guardado, en cuyo caso `store.failure` describe el motivo.
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }

        switch mode {
        case .create:
            return store.createHabit(
                name: trimmedName,
                notes: notes,
                color: color,
                schedule: schedule
            ) != nil

        case let .edit(habit):
            store.update(
                habit,
                name: trimmedName,
                notes: notes,
                color: color,
                schedule: schedule
            )
            return store.failure == nil
        }
    }

    /// Archiva el hábito conservando su historial.
    func archive() {
        guard let habit = editingHabit else { return }
        store.archive(habit)
    }

    /// Borra el hábito y sus registros. Irreversible: la vista debe confirmar
    /// antes de llamar.
    func delete() {
        guard let habit = editingHabit else { return }
        store.delete(habit)
    }
}
