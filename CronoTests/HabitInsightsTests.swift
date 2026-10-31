import Foundation
import Testing

@testable import Crono

/// Pruebas de las estadísticas por semanas, meses y días de la semana.
///
/// El 14 de septiembre de 2026 es lunes, y las semanas empiezan en lunes.
@Suite("Estadísticas de hábitos")
struct HabitInsightsTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    var insights: HabitInsights { HabitInsights(calendar: calendar) }

    func series(
        schedule: WeekdaySet = .everyDay,
        completed: [DayKey],
        from firstDay: DayKey,
        to lastDay: DayKey,
        counts: [DayKey: Int] = [:],
        target: Int = 1
    ) -> HabitSeries {
        HabitSeries(
            schedule: schedule,
            completed: Set(completed),
            firstDay: firstDay,
            lastDay: lastDay,
            counts: counts,
            target: target
        )
    }

    // MARK: - Semanas

    @Test("Cada semana cuenta sus días programados")
    func weeklyRates() {
        let habit = series(
            schedule: .weekdays,
            completed: [20260914, 20260915, 20260916, 20260917, 20260918, 20260921, 20260922],
            from: 20260914,
            to: 20260927
        )

        let weeks = insights.weeklyRates(for: [habit], weeks: 2, today: 20260927)

        #expect(weeks.map(\.start) == [20260914, 20260921])
        #expect(weeks.map(\.scheduled) == [5, 5])
        #expect(weeks.map(\.fulfilled) == [5, 2])
        #expect(weeks.first?.rate == 1)
    }

    @Test("Una semana sin nada que cumplir no es un cero")
    func emptyWeekHasNoRate() {
        let habit = series(completed: [20260921], from: 20260921, to: 20260921)

        let weeks = insights.weeklyRates(for: [habit], weeks: 3, today: 20260921)

        #expect(weeks.count == 3)
        #expect(weeks[0].rate == nil)
        #expect(weeks[1].rate == nil)
        #expect(weeks[2].rate == 1)
    }

    @Test("Un hábito archivado deja de contar desde su archivo")
    func archivedStopsCounting() {
        let habit = series(completed: [20260914], from: 20260914, to: 20260916)

        let weeks = insights.weeklyRates(for: [habit], weeks: 2, today: 20260927)

        #expect(weeks[0].scheduled == 3)
        #expect(weeks[0].fulfilled == 1)
        #expect(weeks[1].rate == nil)
    }

    @Test("Varios hábitos suman días, no promedian porcentajes")
    func aggregateSumsDays() {
        let daily = series(completed: Array(20260914...20260920), from: 20260914, to: 20260920)
        let weekly = series(schedule: [.monday], completed: [], from: 20260914, to: 20260920)

        let week = insights.weeklyRates(for: [daily, weekly], weeks: 1, today: 20260920)

        // 7 de 8 días, no la media de 100 % y 0 %.
        #expect(week.first?.scheduled == 8)
        #expect(week.first?.fulfilled == 7)
    }

    // MARK: - Meses

    @Test("Los meses van del más antiguo al actual")
    func monthlyRates() {
        let september = Array(20260915...20260930)
        let habit = series(completed: september, from: 20260915, to: 20261014)

        let months = insights.monthlyRates(for: [habit], months: 2, today: 20261015)

        #expect(months.map(\.start) == [20260901, 20261001])
        #expect(months[0].scheduled == 16)
        #expect(months[0].rate == 1)
        #expect(months[1].scheduled == 14)
        #expect(months[1].fulfilled == 0)
    }

    // MARK: - Días de la semana

    @Test("El día flojo es el que menos se cumple")
    func weakestWeekday() {
        var completed: [DayKey] = []
        for day in calendar.dayKeys(from: 20260831, to: 20260927) where calendar.weekday(fromDayKey: day) != 2 {
            completed.append(day)
        }
        let habit = series(completed: completed, from: 20260831, to: 20260927)

        let weakest = insights.weakestWeekday(for: habit)

        #expect(weakest?.weekday == 2)
        #expect(weakest?.rate == 0)
        #expect(weakest?.scheduled == 4)
    }

    @Test("Con un empate gana el primero de la semana")
    func tieGoesToFirst() {
        var completed: [DayKey] = []
        for day in calendar.dayKeys(from: 20260831, to: 20260927) {
            let weekday = calendar.weekday(fromDayKey: day)
            if weekday != 2 && weekday != 3 { completed.append(day) }
        }
        let habit = series(completed: completed, from: 20260831, to: 20260927)

        #expect(insights.weakestWeekday(for: habit)?.weekday == 2)
    }

    @Test("Si todos los días van igual no hay día flojo")
    func noWeakestWhenEven() {
        let habit = series(
            completed: Array(calendar.dayKeys(from: 20260831, to: 20260927)),
            from: 20260831,
            to: 20260927
        )

        #expect(insights.weakestWeekday(for: habit) == nil)
    }

    @Test("Con pocas muestras no se señala ningún día")
    func needsSamples() {
        let habit = series(completed: [20260915], from: 20260914, to: 20260920)

        #expect(insights.weakestWeekday(for: habit) == nil)
    }

    // MARK: - Cantidad

    @Test("La media cuenta los días sin nada como cero")
    func averageCount() {
        let habit = series(
            completed: [20260915],
            from: 20260914,
            to: 20260915,
            counts: [20260914: 4, 20260915: 8],
            target: 8
        )

        #expect(insights.averageCount(for: habit, days: 3, today: 20260916) == 6)

        // Si hoy ya se apuntó algo, hoy entra en la media.
        let withToday = series(
            completed: [20260915],
            from: 20260914,
            to: 20260915,
            counts: [20260914: 4, 20260915: 8, 20260916: 3],
            target: 8
        )
        #expect(insights.averageCount(for: withToday, days: 3, today: 20260916) == 5)
    }
}
