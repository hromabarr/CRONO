import Foundation

/// El cumplimiento de un periodo: una semana o un mes.
struct PeriodRate: Identifiable, Equatable, Sendable {
    /// Primer día del periodo.
    let start: DayKey
    /// El mismo día como fecha, para el eje de los gráficos.
    let date: Date
    /// Días programados que había que cumplir en el periodo.
    let scheduled: Int
    let fulfilled: Int

    var id: DayKey { start }

    /// `nil` si no había nada que cumplir: un periodo vacío no es un 0 %.
    var rate: Double? {
        scheduled > 0 ? Double(fulfilled) / Double(scheduled) : nil
    }
}

/// El cumplimiento de un día de la semana a lo largo de todo el historial.
struct WeekdayRate: Equatable, Sendable {
    /// Convención de Foundation: 1 es domingo, 7 sábado.
    let weekday: Int
    let scheduled: Int
    let fulfilled: Int

    var rate: Double {
        scheduled > 0 ? Double(fulfilled) / Double(scheduled) : 0
    }
}

/// Un hábito reducido a lo que necesitan las estadísticas.
///
/// Es un valor y no el `@Model`, para que los cálculos sean puros y se puedan
/// probar con días escritos a mano.
struct HabitSeries: Sendable {
    let schedule: WeekdaySet
    let completed: Set<DayKey>
    /// Primer día que cuenta.
    let firstDay: DayKey
    /// Último día que cuenta: hoy si ya se cumplió, ayer si aún está pendiente
    /// —hoy no es un fallo hasta que acaba—, o el día en que se archivó.
    let lastDay: DayKey
    /// Lo apuntado cada día, para los hábitos con cantidad.
    let counts: [DayKey: Int]
    let target: Int
}

extension HabitSeries {
    init(habit: Habit, today: DayKey, calendar: Calendar = AppCalendar.current) {
        let completed = habit.completedDayKeys
        let streaks = StreakCalculator(calendar: calendar)
        var last = streaks.effectiveEnd(schedule: habit.schedule, completed: completed, today: today)
        if let archivedAt = habit.archivedAt {
            last = min(last, calendar.dayKey(from: archivedAt))
        }

        var counts: [DayKey: Int] = [:]
        for completion in habit.completions {
            counts[completion.dayKey] = completion.count
        }

        self.init(
            schedule: habit.schedule,
            completed: completed,
            firstDay: habit.createdDayKey,
            lastDay: last,
            counts: counts,
            target: habit.targetCount
        )
    }
}

/// Estadísticas de cumplimiento por semanas, meses y días de la semana.
///
/// Todas cuentan igual que el porcentaje del historial: solo los días
/// programados, solo entre el alta y el último día que cuenta, y un día cuenta
/// como cumplido si llegó al objetivo.
struct HabitInsights {
    let calendar: Calendar

    init(calendar: Calendar = AppCalendar.current) {
        self.calendar = calendar
    }

    // MARK: - Semanas y meses

    /// Las últimas `weeks` semanas, de la más antigua a la actual.
    ///
    /// Con varios hábitos suma lo de todos: es el cumplimiento global, no la
    /// media de los porcentajes, para que un hábito de un día a la semana no
    /// pese lo mismo que uno diario.
    func weeklyRates(for series: [HabitSeries], weeks: Int, today: DayKey) -> [PeriodRate] {
        guard weeks > 0, let todayDate = calendar.date(fromDayKey: today),
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: todayDate)?.start
        else { return [] }

        var result: [PeriodRate] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .day, value: 6, to: start)
            else { continue }
            result.append(rate(for: series, from: start, to: end))
        }
        return result
    }

    /// Los últimos `months` meses, del más antiguo al actual.
    func monthlyRates(for series: [HabitSeries], months: Int, today: DayKey) -> [PeriodRate] {
        guard months > 0, let todayDate = calendar.date(fromDayKey: today),
              let thisMonth = calendar.dateInterval(of: .month, for: todayDate)?.start
        else { return [] }

        var result: [PeriodRate] = []
        for offset in stride(from: months - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: thisMonth),
                  let next = calendar.date(byAdding: .month, value: 1, to: start),
                  let end = calendar.date(byAdding: .day, value: -1, to: next)
            else { continue }
            result.append(rate(for: series, from: start, to: end))
        }
        return result
    }

    private func rate(for series: [HabitSeries], from start: Date, to end: Date) -> PeriodRate {
        let startKey = calendar.dayKey(from: start)
        let endKey = calendar.dayKey(from: end)
        var scheduled = 0
        var fulfilled = 0

        for habit in series {
            let first = max(startKey, habit.firstDay)
            let last = min(endKey, habit.lastDay)
            guard first <= last else { continue }

            for day in calendar.dayKeys(from: first, to: last) where isScheduled(day, in: habit.schedule) {
                scheduled += 1
                if habit.completed.contains(day) { fulfilled += 1 }
            }
        }

        return PeriodRate(start: startKey, date: start, scheduled: scheduled, fulfilled: fulfilled)
    }

    // MARK: - Días de la semana

    /// El cumplimiento de cada día de la semana programado, en el orden de la
    /// semana del usuario.
    func weekdayRates(for habit: HabitSeries) -> [WeekdayRate] {
        var scheduled: [Int: Int] = [:]
        var fulfilled: [Int: Int] = [:]

        if habit.firstDay <= habit.lastDay {
            for day in calendar.dayKeys(from: habit.firstDay, to: habit.lastDay) {
                guard let weekday = calendar.weekday(fromDayKey: day),
                      habit.schedule.contains(weekday: weekday)
                else { continue }
                scheduled[weekday, default: 0] += 1
                if habit.completed.contains(day) { fulfilled[weekday, default: 0] += 1 }
            }
        }

        var result: [WeekdayRate] = []
        for offset in 0..<7 {
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            guard let count = scheduled[weekday] else { continue }
            result.append(WeekdayRate(weekday: weekday, scheduled: count, fulfilled: fulfilled[weekday] ?? 0))
        }
        return result
    }

    /// El día de la semana que más se falla, si hay uno que destaque.
    ///
    /// Hace falta haberlo tenido programado al menos `minimumSamples` veces:
    /// con un solo lunes, «tu día flojo es el lunes» sería ruido. Y tiene que
    /// estar por debajo del resto; si todos van igual, no hay día flojo. Con un
    /// empate gana el primero de la semana, para que la frase no cambie sola.
    func weakestWeekday(for habit: HabitSeries, minimumSamples: Int = 3) -> WeekdayRate? {
        let candidates = weekdayRates(for: habit).filter { $0.scheduled >= minimumSamples }
        guard candidates.count >= 2 else { return nil }

        var weakest = candidates[0]
        for candidate in candidates.dropFirst() where candidate.rate < weakest.rate {
            weakest = candidate
        }

        let best = candidates.map(\.rate).max() ?? 0
        guard weakest.rate < best else { return nil }
        return weakest
    }

    // MARK: - Cantidad

    /// La media apuntada en los días programados de los últimos `days` días.
    ///
    /// Cuenta los días sin nada como cero: la media de los días que sí se
    /// apuntaron diría que todo va bien justo cuando no.
    func averageCount(for habit: HabitSeries, days: Int, today: DayKey) -> Double? {
        guard let start = calendar.dayKey(today, offsetByDays: -(days - 1)) else { return nil }
        let first = max(start, habit.firstDay)
        // Hoy entra si ya se apuntó algo: un día a medias no es un cero, pero
        // tampoco hay que esperar a que acabe para contar lo hecho.
        let last = habit.counts[today] == nil ? habit.lastDay : max(habit.lastDay, today)
        guard first <= last else { return nil }

        var total = 0
        var scheduled = 0
        for day in calendar.dayKeys(from: first, to: last) where isScheduled(day, in: habit.schedule) {
            scheduled += 1
            total += habit.counts[day] ?? 0
        }
        guard scheduled > 0 else { return nil }
        return Double(total) / Double(scheduled)
    }

    // MARK: - Auxiliares

    private func isScheduled(_ day: DayKey, in schedule: WeekdaySet) -> Bool {
        guard let weekday = calendar.weekday(fromDayKey: day) else { return false }
        return schedule.contains(weekday: weekday)
    }
}
