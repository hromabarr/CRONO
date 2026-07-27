import Foundation

/// Estadísticas de cumplimiento de un hábito en una ventana de tiempo.
struct HabitStats: Equatable, Sendable {
    var currentStreak: Int
    var bestStreak: Int
    /// Fracción entre 0 y 1 de los días programados que se cumplieron.
    var completionRate: Double

    static let zero = HabitStats(currentStreak: 0, bestStreak: 0, completionRate: 0)
}

/// Calcula rachas y porcentajes de cumplimiento.
///
/// Es deliberadamente puro: no conoce SwiftData, no lee el reloj y no guarda
/// estado. Todo entra por parámetro —incluida la fecha de "hoy"— para que cada
/// regla se pueda probar sin simulador y sin esperar a que cambie el día.
///
/// ## Reglas
///
/// 1. Solo se evalúan los días programados del hábito. Un lunes libre en un
///    hábito de martes y jueves no interrumpe nada.
/// 2. Un día programado sin marcar **rompe** la racha.
/// 3. **Excepción de cortesía:** si hoy está programado y aún no se ha marcado,
///    no cuenta como fallo. La racha refleja el estado hasta ayer. Sin esta
///    regla, todas las rachas aparecerían a cero cada mañana.
/// 4. Los días anteriores a la creación del hábito no cuentan como fallos.
struct StreakCalculator {
    let calendar: Calendar

    init(calendar: Calendar = AppCalendar.current) {
        self.calendar = calendar
    }

    // MARK: - Ventana de evaluación

    /// Último día que se considera al medir rachas.
    ///
    /// Es ayer cuando hoy toca y todavía está sin marcar (regla 3); en cualquier
    /// otro caso es hoy. Centralizarlo aquí garantiza que la racha actual, la
    /// mejor racha y el porcentaje apliquen la cortesía de forma idéntica.
    func effectiveEnd(
        schedule: WeekdaySet,
        completed: Set<DayKey>,
        today: DayKey
    ) -> DayKey {
        let pendingToday = isScheduled(today, in: schedule) && !completed.contains(today)
        guard pendingToday else { return today }
        return calendar.dayKey(today, offsetByDays: -1) ?? today
    }

    // MARK: - Rachas

    /// Días programados consecutivos cumplidos hasta hoy.
    func currentStreak(
        schedule: WeekdaySet,
        completed: Set<DayKey>,
        createdDayKey: DayKey,
        today: DayKey
    ) -> Int {
        // Sin días programados no hay nada que encadenar; además, seguir
        // adelante haría que el bucle no encontrara nunca un día que evaluar.
        guard !schedule.isEmpty else { return 0 }

        let end = effectiveEnd(schedule: schedule, completed: completed, today: today)
        var streak = 0
        var cursor = end

        // `DayKey` es `yyyyMMdd`, así que el orden numérico es el cronológico.
        while cursor >= createdDayKey {
            if isScheduled(cursor, in: schedule) {
                guard completed.contains(cursor) else { break }
                streak += 1
            }
            guard let previous = calendar.dayKey(cursor, offsetByDays: -1) else { break }
            cursor = previous
        }

        return streak
    }

    /// Racha más larga conseguida desde la creación del hábito.
    func bestStreak(
        schedule: WeekdaySet,
        completed: Set<DayKey>,
        createdDayKey: DayKey,
        today: DayKey
    ) -> Int {
        guard !schedule.isEmpty else { return 0 }

        let end = effectiveEnd(schedule: schedule, completed: completed, today: today)
        guard createdDayKey <= end else { return 0 }

        var best = 0
        var run = 0

        for dayKey in calendar.dayKeys(from: createdDayKey, to: end) {
            guard isScheduled(dayKey, in: schedule) else { continue }
            if completed.contains(dayKey) {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }

        return best
    }

    // MARK: - Porcentaje

    /// Fracción de días programados cumplidos en un intervalo cerrado.
    ///
    /// Devuelve 0 si el intervalo no contiene ningún día programado, que es lo
    /// honesto: no hay nada que cumplir, así que tampoco un 100 % que presumir.
    func completionRate(
        schedule: WeekdaySet,
        completed: Set<DayKey>,
        from start: DayKey,
        to end: DayKey
    ) -> Double {
        guard !schedule.isEmpty else { return 0 }

        let scheduledDays = calendar
            .dayKeys(from: start, to: end)
            .filter { isScheduled($0, in: schedule) }

        guard !scheduledDays.isEmpty else { return 0 }

        let fulfilled = scheduledDays.filter { completed.contains($0) }.count
        return Double(fulfilled) / Double(scheduledDays.count)
    }

    // MARK: - Conjunto

    /// Las tres estadísticas de una vez, para no recorrer el historial por
    /// separado en cada una.
    func stats(
        schedule: WeekdaySet,
        completed: Set<DayKey>,
        createdDayKey: DayKey,
        today: DayKey,
        rateFrom rateStart: DayKey? = nil
    ) -> HabitStats {
        let end = effectiveEnd(schedule: schedule, completed: completed, today: today)
        return HabitStats(
            currentStreak: currentStreak(
                schedule: schedule,
                completed: completed,
                createdDayKey: createdDayKey,
                today: today
            ),
            bestStreak: bestStreak(
                schedule: schedule,
                completed: completed,
                createdDayKey: createdDayKey,
                today: today
            ),
            completionRate: completionRate(
                schedule: schedule,
                completed: completed,
                from: max(rateStart ?? createdDayKey, createdDayKey),
                to: end
            )
        )
    }

    // MARK: - Auxiliares

    /// Indica si un día cae en la programación semanal, sin mirar fechas de
    /// creación: acotar por creación es responsabilidad de quien llama.
    private func isScheduled(_ dayKey: DayKey, in schedule: WeekdaySet) -> Bool {
        guard let weekday = calendar.weekday(fromDayKey: dayKey) else { return false }
        return schedule.contains(weekday: weekday)
    }
}

// MARK: - Puente con el modelo

/// Envoltorios de conveniencia sobre `Habit`.
///
/// Están separados a propósito: el cálculo de arriba no depende de SwiftData y se
/// puede probar con datos sintéticos; esto solo extrae los campos del modelo.
extension StreakCalculator {
    func stats(for habit: Habit, today: DayKey, rateFrom rateStart: DayKey? = nil) -> HabitStats {
        stats(
            schedule: habit.schedule,
            completed: habit.completedDayKeys,
            createdDayKey: habit.createdDayKey,
            today: today,
            rateFrom: rateStart
        )
    }

    func currentStreak(for habit: Habit, today: DayKey) -> Int {
        currentStreak(
            schedule: habit.schedule,
            completed: habit.completedDayKeys,
            createdDayKey: habit.createdDayKey,
            today: today
        )
    }
}
