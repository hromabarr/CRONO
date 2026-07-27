import Foundation
import Observation

/// Estado derivado y acciones de la pantalla Hoy.
///
/// ## Por qué recibe los hábitos en lugar de consultarlos
///
/// La vista los obtiene con `@Query`, que es la fuente reactiva de SwiftData:
/// cuando cambia un dato, la vista se redibuja sola. Si este ViewModel hiciera
/// el `fetch`, habría que refrescarlo a mano tras cada mutación y la reactividad
/// se perdería. Así que la división es: la vista trae los datos, el ViewModel
/// deriva y actúa.
@MainActor
@Observable
final class TodayViewModel {
    private let store: HabitStore
    private let calendar: Calendar

    /// El día que la pantalla considera "hoy". No es una constante: la app puede
    /// quedarse abierta y cruzar la medianoche.
    private(set) var today: DayKey

    init(
        store: HabitStore,
        calendar: Calendar = AppCalendar.current,
        today: DayKey? = nil
    ) {
        self.store = store
        self.calendar = calendar
        self.today = today ?? Date.now.dayKey
    }

    // MARK: - Fecha

    /// Fecha de hoy escrita para la cabecera: "lunes, 27 de julio".
    var todayTitle: String {
        calendar.displayString(
            forDayKey: today,
            style: .dateTime.weekday(.wide).day().month(.wide)
        )
    }

    /// Vuelve a leer el día actual.
    ///
    /// La vista lo llama al volver a primer plano: si el usuario dejó la app
    /// abierta anoche, `today` apunta a ayer y la lista mostraría el día
    /// equivocado con las marcas de ayer puestas.
    func refreshToday() {
        let current = Date.now.dayKey
        if current != today { today = current }
    }

    // MARK: - Selección

    /// Los hábitos activos que toca cumplir hoy, en el orden del usuario.
    func habitsScheduledToday(from habits: [Habit]) -> [Habit] {
        habits
            .filter { $0.isActive && $0.isScheduled(on: today, calendar: calendar) }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    func isCompletedToday(_ habit: Habit) -> Bool {
        habit.isCompleted(on: today)
    }

    // MARK: - Progreso

    struct DayProgress: Equatable {
        var completed: Int
        var total: Int

        /// Entre 0 y 1. Un día sin hábitos programados es 0, no 100 %: no hay
        /// nada hecho, simplemente no había nada que hacer.
        var fraction: Double {
            total == 0 ? 0 : Double(completed) / Double(total)
        }

        var percentText: String { "\(Int((fraction * 100).rounded()))%" }
        var countText: String { "\(completed) de \(total)" }
        var isComplete: Bool { total > 0 && completed == total }
        var remaining: Int { max(0, total - completed) }
    }

    func progress(for scheduledHabits: [Habit]) -> DayProgress {
        DayProgress(
            completed: scheduledHabits.filter { isCompletedToday($0) }.count,
            total: scheduledHabits.count
        )
    }

    /// Titular específico del estado. Un texto genérico sirve para todos los
    /// casos y no dice nada en ninguno.
    func headline(for progress: DayProgress) -> String {
        if progress.total == 0 { return "Nada programado" }
        if progress.completed == 0 { return "Empieza el día" }
        if progress.isComplete { return "Día completo" }
        return "Vas por buen camino"
    }

    func detail(for progress: DayProgress) -> String {
        if progress.total == 0 {
            return "Hoy no toca ningún hábito. Puedes añadir uno desde Hábitos."
        }
        if progress.isComplete {
            return progress.total == 1
                ? "El único hábito de hoy, hecho."
                : "Los \(progress.total) hábitos de hoy, hechos."
        }
        if progress.completed == 0 {
            return progress.total == 1
                ? "Tienes 1 hábito programado para hoy."
                : "Tienes \(progress.total) hábitos programados para hoy."
        }
        // El verbo concuerda con el número, no solo el sustantivo.
        return progress.remaining == 1
            ? "Te queda 1 hábito por marcar."
            : "Te quedan \(progress.remaining) hábitos por marcar."
    }

    // MARK: - Acciones

    func toggle(_ habit: Habit) {
        store.toggleCompletion(for: habit, on: today, today: today)
    }

    /// Etiqueta de accesibilidad de la fila: estado y acción, porque el relleno
    /// del círculo no se transmite por sí solo a VoiceOver.
    func accessibilityLabel(for habit: Habit) -> String {
        let state = isCompletedToday(habit) ? "completado" : "sin completar"
        return "\(habit.name), \(state)"
    }

    func accessibilityHint(for habit: Habit) -> String {
        isCompletedToday(habit) ? "Toca para desmarcar" : "Toca para marcar como completado"
    }
}
