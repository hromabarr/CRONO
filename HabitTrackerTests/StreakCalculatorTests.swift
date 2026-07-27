import Foundation
import Testing

@testable import HabitTracker

/// Pruebas de la lógica de rachas.
///
/// Se inyecta un calendario en UTC con la semana empezando en lunes para que los
/// resultados no dependan de la zona horaria ni de la configuración regional de
/// la máquina que ejecuta las pruebas.
@Suite("Cálculo de rachas")
struct StreakCalculatorTests {

    // MARK: - Contexto

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "es_ES")
        calendar.firstWeekday = 2
        return calendar
    }()

    var calculator: StreakCalculator { StreakCalculator(calendar: calendar) }

    /// Clave de día, con julio de 2026 por defecto.
    func key(_ day: Int, month: Int = 7, year: Int = 2026) -> DayKey {
        year * 10_000 + month * 100 + day
    }

    /// Lunes según Foundation, donde 1 = domingo y 7 = sábado.
    static let monday = 2

    var mondayWednesdayFriday: WeekdaySet {
        [.monday, .wednesday, .friday]
    }

    // MARK: - Supuestos del calendario

    /// Fija las fechas sobre las que se construyen las demás pruebas.
    ///
    /// Si este test falla, las fechas elegidas para los otros ya no significan
    /// lo que creo, y sus resultados dejan de tener valor. Va primero a
    /// propósito: es el cimiento, no un detalle.
    @Test("Julio de 2026 empieza en miércoles y el día 27 es lunes")
    func calendarAssumptions() {
        #expect(calendar.weekday(fromDayKey: key(1)) == 4)  // miércoles
        #expect(calendar.weekday(fromDayKey: key(27)) == Self.monday)
        #expect(calendar.numberOfDays(in: MonthIdentifier(year: 2026, month: 7)) == 31)
        // Con la semana empezando en lunes, un mes que abre en miércoles
        // deja dos huecos.
        #expect(calendar.leadingBlankDays(in: MonthIdentifier(year: 2026, month: 7)) == 2)
    }

    // MARK: - Regla 1: los días no programados no interrumpen

    @Test("Un hábito de lunes, miércoles y viernes no rompe racha el fin de semana")
    func weekendDoesNotBreakStreak() {
        // Cumplido lunes 20, miércoles 22, viernes 24 y lunes 27.
        // Entre el 24 y el 27 hay sábado y domingo, que no cuentan.
        let completed: Set<DayKey> = [key(20), key(22), key(24), key(27)]

        let streak = calculator.currentStreak(
            schedule: mondayWednesdayFriday,
            completed: completed,
            createdDayKey: key(1),
            today: key(27)
        )

        #expect(streak == 4)
    }

    // MARK: - Regla 2: un día programado sin marcar rompe

    @Test("Un día programado sin cumplir corta la racha")
    func missedScheduledDayBreaksStreak() {
        // Falta el viernes 17: la racha solo puede llegar hasta el 20.
        let completed: Set<DayKey> = [key(20), key(22), key(24), key(27)]

        let streak = calculator.currentStreak(
            schedule: mondayWednesdayFriday,
            completed: completed,
            createdDayKey: key(1),
            today: key(27)
        )

        // 27, 24, 22, 20 → 4. El 17 detiene el recuento.
        #expect(streak == 4)

        // Añadir el 17 y el 15 extiende la racha en dos.
        let extended = completed.union([key(17), key(15)])
        #expect(
            calculator.currentStreak(
                schedule: mondayWednesdayFriday,
                completed: extended,
                createdDayKey: key(1),
                today: key(27)
            ) == 6
        )
    }

    // MARK: - Regla 3: cortesía del día en curso

    @Test("Hoy programado y sin marcar no rompe la racha")
    func pendingTodayKeepsStreakFromYesterday() {
        // Todo cumplido hasta el domingo 26, pero hoy (lunes 27) aún no.
        let completed: Set<DayKey> = [key(20), key(22), key(24)]

        let streak = calculator.currentStreak(
            schedule: mondayWednesdayFriday,
            completed: completed,
            createdDayKey: key(1),
            today: key(27)
        )

        // Sin la cortesía saldría 0 y el usuario vería su racha desaparecer
        // cada mañana. La racha refleja el estado hasta ayer: 24, 22, 20.
        #expect(streak == 3)
    }

    @Test("Marcar hoy suma inmediatamente")
    func completingTodayCountsToday() {
        let base: Set<DayKey> = [key(20), key(22), key(24)]

        let before = calculator.currentStreak(
            schedule: mondayWednesdayFriday,
            completed: base,
            createdDayKey: key(1),
            today: key(27)
        )
        let after = calculator.currentStreak(
            schedule: mondayWednesdayFriday,
            completed: base.union([key(27)]),
            createdDayKey: key(1),
            today: key(27)
        )

        #expect(before == 3)
        #expect(after == 4)
    }

    @Test("Si hoy no está programado, la ventana termina hoy")
    func unscheduledTodayDoesNotShiftWindow() {
        // Domingo 26: no toca, así que no hay nada pendiente que perdonar.
        let end = calculator.effectiveEnd(
            schedule: mondayWednesdayFriday,
            completed: [key(24)],
            today: key(26)
        )
        #expect(end == key(26))

        // Lunes 27 sin marcar: la ventana retrocede a ayer.
        let shifted = calculator.effectiveEnd(
            schedule: mondayWednesdayFriday,
            completed: [key(24)],
            today: key(27)
        )
        #expect(shifted == key(26))
    }

    // MARK: - Regla 4: nada anterior a la creación cuenta como fallo

    @Test("Los días previos a la creación no cuentan como fallos")
    func daysBeforeCreationAreNotFailures() {
        // Hábito diario creado el 25, cumplido los tres días de su vida.
        let completed: Set<DayKey> = [key(25), key(26), key(27)]

        let streak = calculator.currentStreak(
            schedule: .everyDay,
            completed: completed,
            createdDayKey: key(25),
            today: key(27)
        )

        #expect(streak == 3)
    }

    @Test("El porcentaje no se diluye con días anteriores a la creación")
    func completionRateStartsAtCreation() {
        let completed: Set<DayKey> = [key(25), key(26), key(27)]

        let rate = calculator.completionRate(
            schedule: .everyDay,
            completed: completed,
            from: key(25),
            to: key(27)
        )

        // Tres de tres. Contar desde el 1 de julio daría un 11 % engañoso.
        #expect(rate == 1.0)
    }

    // MARK: - Mejor racha

    @Test("La mejor racha puede ser muy superior a la actual")
    func bestStreakExceedsCurrent() {
        // Racha larga del 1 al 15, hueco, y una racha corta del 25 al 27.
        var completed = Set((1...15).map { key($0) })
        completed.formUnion([key(25), key(26), key(27)])

        let current = calculator.currentStreak(
            schedule: .everyDay,
            completed: completed,
            createdDayKey: key(1),
            today: key(27)
        )
        let best = calculator.bestStreak(
            schedule: .everyDay,
            completed: completed,
            createdDayKey: key(1),
            today: key(27)
        )

        #expect(current == 3)
        #expect(best == 15)
    }

    @Test("La mejor racha solo cuenta los días programados")
    func bestStreakCountsScheduledDaysOnly() {
        // Todos los lunes, miércoles y viernes de julio hasta el 27.
        let scheduled = [1, 3, 6, 8, 10, 13, 15, 17, 20, 22, 24, 27]
        let completed = Set(scheduled.map { key($0) })

        let best = calculator.bestStreak(
            schedule: mondayWednesdayFriday,
            completed: completed,
            createdDayKey: key(1),
            today: key(27)
        )

        // Doce ocasiones cumplidas seguidas, no 27 días naturales.
        #expect(best == 12)
    }

    // MARK: - Aritmética de fechas

    @Test("Una racha cruza el cambio de mes")
    func streakSpansMonthBoundary() {
        // Del 29 de junio al 2 de julio. Restar 1 al entero yyyyMMdd daría
        // 20260700, que no existe: esto verifica que se usa el calendario.
        let completed: Set<DayKey> = [
            key(29, month: 6), key(30, month: 6),
            key(1), key(2)
        ]

        let streak = calculator.currentStreak(
            schedule: .everyDay,
            completed: completed,
            createdDayKey: key(25, month: 6),
            today: key(2)
        )

        #expect(streak == 4)
    }

    @Test("Una racha cruza el cambio de año")
    func streakSpansYearBoundary() {
        let completed: Set<DayKey> = [
            key(30, month: 12, year: 2025), key(31, month: 12, year: 2025),
            key(1, month: 1, year: 2026), key(2, month: 1, year: 2026)
        ]

        let streak = calculator.currentStreak(
            schedule: .everyDay,
            completed: completed,
            createdDayKey: key(1, month: 12, year: 2025),
            today: key(2, month: 1, year: 2026)
        )

        #expect(streak == 4)
    }

    // MARK: - Porcentaje

    @Test("El porcentaje solo mide los días programados")
    func completionRateUsesScheduledDaysOnly() {
        // Cumplidos 4 de los 12 días que tocaban entre el 1 y el 27.
        let completed: Set<DayKey> = [key(20), key(22), key(24), key(27)]

        let rate = calculator.completionRate(
            schedule: mondayWednesdayFriday,
            completed: completed,
            from: key(1),
            to: key(27)
        )

        #expect(abs(rate - 4.0 / 12.0) < 0.0001)
    }

    @Test("Un intervalo sin días programados da 0, no 100 %")
    func emptyRangeGivesZeroRate() {
        // Sábado 25 y domingo 26 en un hábito de lunes, miércoles y viernes.
        let rate = calculator.completionRate(
            schedule: mondayWednesdayFriday,
            completed: [],
            from: key(25),
            to: key(26)
        )

        // Un 100 % aquí presumiría de un cumplimiento que no existió.
        #expect(rate == 0)
    }

    // MARK: - Casos límite

    @Test("Un hábito sin días programados no produce rachas")
    func emptyScheduleYieldsZero() {
        let empty: WeekdaySet = []

        #expect(
            calculator.currentStreak(
                schedule: empty,
                completed: [key(27)],
                createdDayKey: key(1),
                today: key(27)
            ) == 0
        )
        #expect(
            calculator.bestStreak(
                schedule: empty,
                completed: [key(27)],
                createdDayKey: key(1),
                today: key(27)
            ) == 0
        )
        #expect(
            calculator.completionRate(
                schedule: empty,
                completed: [key(27)],
                from: key(1),
                to: key(27)
            ) == 0
        )
    }

    @Test("Un hábito creado hoy y sin marcar no da racha negativa ni bucle")
    func habitCreatedTodayIsSafe() {
        let stats = calculator.stats(
            schedule: .everyDay,
            completed: [],
            createdDayKey: key(27),
            today: key(27)
        )

        // La ventana efectiva retrocede al 26, anterior a la creación, así que
        // no hay ningún día que evaluar.
        #expect(stats.currentStreak == 0)
        #expect(stats.bestStreak == 0)
        #expect(stats.completionRate == 0)
    }

    @Test("Un hábito diario perfecto desde su creación llega al 100 %")
    func perfectHabitReportsFullRate() {
        let completed = Set((20...27).map { key($0) })

        let stats = calculator.stats(
            schedule: .everyDay,
            completed: completed,
            createdDayKey: key(20),
            today: key(27)
        )

        #expect(stats.currentStreak == 8)
        #expect(stats.bestStreak == 8)
        #expect(stats.completionRate == 1.0)
    }
}
