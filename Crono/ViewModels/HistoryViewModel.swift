import Foundation
import Observation

/// Estado derivado de la pantalla Historial: rejilla del mes y estadísticas.
///
/// Igual que `TodayViewModel`, recibe los hábitos desde el `@Query` de la vista
/// en lugar de consultarlos, para no romper la reactividad de SwiftData.
@MainActor
@Observable
final class HistoryViewModel {
    private let calculator: StreakCalculator
    private let calendar: Calendar

    let today: DayKey

    /// Mes que se está mirando. Empieza en el mes actual.
    var visibleMonth: MonthIdentifier

    init(
        calendar: Calendar = AppCalendar.current,
        calculator: StreakCalculator? = nil,
        today: DayKey? = nil
    ) {
        let resolvedToday = today ?? Date.now.dayKey
        self.calendar = calendar
        self.calculator = calculator ?? StreakCalculator(calendar: calendar)
        self.today = resolvedToday
        self.visibleMonth = calendar.monthIdentifier(from: resolvedToday)
    }

    // MARK: - Navegación entre meses

    var monthTitle: String { calendar.monthTitle(visibleMonth) }

    /// Solo el nombre del mes, para etiquetas cortas como la del porcentaje.
    var monthName: String { calendar.monthName(visibleMonth) }

    /// No se navega al futuro: no hay nada que ver y sugeriría que se pueden
    /// marcar días que aún no han llegado.
    var canGoForward: Bool {
        visibleMonth < calendar.monthIdentifier(from: today)
    }

    func goToPreviousMonth() {
        visibleMonth = calendar.month(visibleMonth, offsetByMonths: -1)
    }

    func goToNextMonth() {
        guard canGoForward else { return }
        visibleMonth = calendar.month(visibleMonth, offsetByMonths: 1)
    }

    func goToCurrentMonth() {
        visibleMonth = calendar.monthIdentifier(from: today)
    }

    // MARK: - Rejilla del mes

    enum DayState: Equatable {
        /// Hueco de relleno antes del día 1.
        case blank
        case past
        case today
        case future
    }

    struct DayCell: Identifiable, Equatable {
        /// Posición en la rejilla; los huecos también necesitan identidad.
        let id: Int
        let dayKey: DayKey?
        let dayNumber: Int?
        /// Fracción de hábitos programados que se cumplieron ese día, 0…1.
        let fraction: Double
        let state: DayState

        var isPerfect: Bool { fraction >= 1 }
    }

    /// Las celdas del mes visible, incluidos los huecos iniciales.
    func cells(for habits: [Habit]) -> [DayCell] {
        let dayCount = calendar.numberOfDays(in: visibleMonth)
        let blanks = calendar.leadingBlankDays(in: visibleMonth)
        let fractions = dailyFractions(for: habits, in: visibleMonth)

        var cells: [DayCell] = (0..<blanks).map { index in
            DayCell(id: index, dayKey: nil, dayNumber: nil, fraction: 0, state: .blank)
        }

        guard dayCount > 0 else { return cells }

        for day in 1...dayCount {
            guard let dayKey = calendar.dayKey(in: visibleMonth, day: day) else { continue }
            let state: DayState = if dayKey == today { .today }
                else if dayKey > today { .future }
                else { .past }

            cells.append(
                DayCell(
                    id: blanks + day,
                    dayKey: dayKey,
                    dayNumber: day,
                    fraction: fractions[dayKey] ?? 0,
                    state: state
                )
            )
        }

        return cells
    }

    /// Fracción cumplida de cada día del mes.
    ///
    /// Se calcula en una sola pasada por hábito y día porque tanto la rejilla
    /// como la racha agregada necesitan exactamente este dato.
    private func dailyFractions(
        for habits: [Habit],
        in month: MonthIdentifier
    ) -> [DayKey: Double] {
        let dayCount = calendar.numberOfDays(in: month)
        guard dayCount > 0, !habits.isEmpty else { return [:] }

        // Los conjuntos de compleciones se materializan una vez, no por día.
        let snapshots = habits.map { HabitSnapshot($0) }
        var result: [DayKey: Double] = [:]

        for day in 1...dayCount {
            guard let dayKey = calendar.dayKey(in: month, day: day),
                  dayKey <= today,
                  let weekday = calendar.weekday(fromDayKey: dayKey)
            else { continue }

            let due = snapshots.filter {
                $0.schedule.contains(weekday: weekday) && dayKey >= $0.createdDayKey
            }
            guard !due.isEmpty else { continue }

            let done = due.filter { $0.completed.contains(dayKey) }.count
            result[dayKey] = Double(done) / Double(due.count)
        }

        return result
    }

    // MARK: - Estadísticas agregadas

    /// Racha de **días perfectos**: días en los que se cumplieron todos los
    /// hábitos que tocaban.
    ///
    /// Es la definición que hace coherente el calendario con las cifras: un día
    /// pintado a relleno completo es un día que cuenta para la racha. Contar
    /// "días con al menos un hábito" daría un número más bonito y sin sentido.
    func aggregateStats(for habits: [Habit]) -> HabitStats {
        let active = habits.filter(\.isActive)
        guard !active.isEmpty else { return .zero }

        let snapshots = active.map { HabitSnapshot($0) }
        let unionSchedule = snapshots.reduce(into: WeekdaySet()) { $0.formUnion($1.schedule) }
        guard let earliest = snapshots.map(\.createdDayKey).min() else { return .zero }

        var perfectDays: Set<DayKey> = []
        for dayKey in calendar.dayKeys(from: earliest, to: today) {
            guard let weekday = calendar.weekday(fromDayKey: dayKey) else { continue }
            let due = snapshots.filter {
                $0.schedule.contains(weekday: weekday) && dayKey >= $0.createdDayKey
            }
            guard !due.isEmpty else { continue }
            if due.allSatisfy({ $0.completed.contains(dayKey) }) {
                perfectDays.insert(dayKey)
            }
        }

        // El porcentaje se acota al mes visible; las rachas, a toda la historia.
        let monthStart = calendar.dayKey(in: visibleMonth, day: 1) ?? earliest

        return HabitStats(
            currentStreak: calculator.currentStreak(
                schedule: unionSchedule,
                completed: perfectDays,
                createdDayKey: earliest,
                today: today
            ),
            bestStreak: calculator.bestStreak(
                schedule: unionSchedule,
                completed: perfectDays,
                createdDayKey: earliest,
                today: today
            ),
            completionRate: calculator.completionRate(
                schedule: unionSchedule,
                completed: perfectDays,
                from: max(monthStart, earliest),
                to: min(monthEnd(of: visibleMonth), today)
            )
        )
    }

    /// Racha actual de un hábito, lista para dibujar.
    ///
    /// Es un tipo con nombre y no una tupla `(habit:streak:)` a propósito: una
    /// tupla con etiquetas atravesando un `ForEach` con `id:` por key path hacía
    /// que el inferidor de tipos de Swift se rindiera al compilar la vista. Con
    /// un `Identifiable` de verdad, el `ForEach` no tiene nada que deducir.
    struct StreakEntry: Identifiable {
        let habit: Habit
        let streak: Int

        var id: UUID { habit.uuid }
    }

    /// Racha actual de cada hábito, de mayor a menor.
    func streaks(for habits: [Habit]) -> [StreakEntry] {
        habits
            .filter(\.isActive)
            .map { StreakEntry(habit: $0, streak: calculator.currentStreak(for: $0, today: today)) }
            .sorted { $0.streak > $1.streak }
    }

    /// Etiqueta de accesibilidad de una celda: sin ella, el arco de progreso es
    /// invisible para VoiceOver.
    func accessibilityLabel(for cell: DayCell) -> String? {
        guard let dayKey = cell.dayKey else { return nil }
        let date = calendar.displayString(forDayKey: dayKey, style: .dateTime.day().month(.wide))

        switch cell.state {
        case .blank:
            return nil
        case .future:
            return "\(date), día futuro"
        case .today:
            return "Hoy, \(date), \(Int((cell.fraction * 100).rounded()))% completado"
        case .past:
            return "\(date), \(Int((cell.fraction * 100).rounded()))% completado"
        }
    }

    // MARK: - Internos

    private func monthEnd(of month: MonthIdentifier) -> DayKey {
        let dayCount = calendar.numberOfDays(in: month)
        return calendar.dayKey(in: month, day: dayCount) ?? today
    }
}

/// Copia inmutable de los campos de un hábito que hacen falta para calcular.
///
/// Materializa la relación `completions` una sola vez. Leerla dentro de un bucle
/// por días dispararía la carga diferida de SwiftData en cada iteración.
private struct HabitSnapshot {
    let schedule: WeekdaySet
    let createdDayKey: DayKey
    let completed: Set<DayKey>

    init(_ habit: Habit) {
        self.schedule = habit.schedule
        self.createdDayKey = habit.createdDayKey
        self.completed = habit.completedDayKeys
    }
}
