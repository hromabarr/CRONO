import Foundation
import Testing

@testable import Crono

/// Pruebas de la calculadora de ciclos de sueño.
///
/// Todo con calendario en UTC y fechas fijas: el cálculo cruza la medianoche en
/// casi todos los casos, que es justo donde la aritmética de horas se rompe.
@Suite("Ciclos de sueño")
struct SleepCycleCalculatorTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    var calculator: SleepCycleCalculator {
        SleepCycleCalculator(
            cycleMinutes: 90,
            latencyMinutes: 15,
            offeredCycles: [6, 5, 4],
            calendar: calendar
        )
    }

    /// 14 de septiembre de 2026 a la hora indicada, en UTC.
    func date(_ hour: Int, _ minute: Int, day: Int = 14) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    func text(_ date: Date) -> String {
        let parts = calendar.dateComponents([.day, .hour, .minute], from: date)
        return String(format: "%d %02d:%02d", parts.day!, parts.hour!, parts.minute!)
    }

    // MARK: - Próxima ocurrencia

    @Test("Una alarma cuya hora ya pasó hoy se refiere a la de mañana")
    func nextOccurrenceRollsToTomorrow() {
        // A las 23:00, «las 7:00» es mañana, no el despertador que ya sonó.
        let next = calculator.nextOccurrence(ofMinuteOfDay: 7 * 60, after: date(23, 0))
        #expect(text(next!) == "15 07:00")
    }

    @Test("Una alarma que aún no ha llegado hoy es de hoy")
    func nextOccurrenceStaysToday() {
        let next = calculator.nextOccurrence(ofMinuteOfDay: 23 * 60 + 30, after: date(22, 0))
        #expect(text(next!) == "14 23:30")
    }

    // MARK: - Horas de acostarse

    @Test("Las horas de acostarse retroceden ciclo a ciclo desde la alarma")
    func bedtimesStepBackByCycle() {
        // Alarma a las 7:00 consultada a las 22:00 del día anterior.
        // 6 ciclos = 9 h + 15 min de latencia → 21:45
        // 5 ciclos = 7 h 30 + 15 → 23:15
        // 4 ciclos = 6 h + 15 → 00:45
        let options = calculator.options(forWakeMinuteOfDay: 7 * 60, now: date(22, 0))

        #expect(options.count == 3)
        #expect(text(options[0].bedtime) == "14 21:45")
        #expect(text(options[1].bedtime) == "14 23:15")
        #expect(text(options[2].bedtime) == "15 00:45")

        // Todas apuntan al mismo despertador.
        //
        // El resultado se ata a una variable antes del `#expect`: `allSatisfy` es
        // `rethrows`, y dentro de la expansión de la macro el compilador pierde
        // la inferencia de que el cierre no lanza y exige un `try`.
        let sameWakeTime = options.allSatisfy { text($0.wakeTime) == "15 07:00" }
        #expect(sameWakeTime)
    }

    @Test("Se marca la opción cuya hora de acostarse ya pasó")
    func pastOptionsAreMarked() {
        // A las 22:00 la de 6 ciclos (21:45) ya no se alcanza.
        let options = calculator.options(forWakeMinuteOfDay: 7 * 60, now: date(22, 0))

        #expect(options[0].isPast)
        #expect(options[1].isPast == false)
        #expect(options[2].isPast == false)
    }

    @Test("A primera hora de la tarde todavía se alcanzan todas")
    func earlyEveningKeepsEveryOption() {
        let options = calculator.options(forWakeMinuteOfDay: 7 * 60, now: date(20, 0))
        let noneMissed = options.allSatisfy { $0.isPast == false }
        #expect(noneMissed)
    }

    @Test("De madrugada ya no se alcanza casi ninguna")
    func lateNightLosesMostOptions() {
        // A la 1:00, para despertar a las 7:00 solo quedan menos de 6 h: ninguna
        // de las tres opciones sigue en pie.
        let options = calculator.options(forWakeMinuteOfDay: 7 * 60, now: date(1, 0))
        let allMissed = options.allSatisfy(\.isPast)
        #expect(allMissed)
    }

    // MARK: - Duración

    @Test("La duración cuenta el sueño, no el rato de conciliarlo")
    func durationExcludesLatency() {
        let options = calculator.options(forWakeMinuteOfDay: 7 * 60, now: date(20, 0))

        #expect(options[0].sleepMinutes == 540)
        #expect(options[1].sleepMinutes == 450)
        #expect(options[2].sleepMinutes == 360)

        // Y el hueco entre acostarse y despertar sí la incluye.
        let gap = calendar.dateComponents(
            [.minute],
            from: options[1].bedtime,
            to: options[1].wakeTime
        ).minute
        #expect(gap == 450 + 15)
    }

    @Test("La duración se escribe en horas y minutos")
    func durationText() {
        let options = calculator.options(forWakeMinuteOfDay: 7 * 60, now: date(20, 0))
        #expect(options[0].durationText == "9 h")
        #expect(options[1].durationText == "7 h 30 min")
        #expect(options[2].durationText == "6 h")
    }

    // MARK: - Acostándose ahora

    @Test("Acostándose ahora se descuenta el rato de dormirse")
    func sleepIfGoingToBedNow() {
        // A las 23:30, con 15 min de latencia, se duerme a las 23:45 y quedan
        // 7 h 15 hasta las 7:00.
        let minutes = calculator.sleepMinutesIfGoingToBedNow(wakeMinuteOfDay: 7 * 60, now: date(23, 30))
        #expect(minutes == 435)
    }

    @Test("Si la alarma suena antes de haberse dormido, no hay cifra")
    func noSleepIfAlarmIsTooSoon() {
        // Alarma a las 7:00 consultada a las 6:50: se dormiría a las 7:05, después
        // de que suene. Devolver «0 minutos» sería peor que no devolver nada.
        let minutes = calculator.sleepMinutesIfGoingToBedNow(wakeMinuteOfDay: 7 * 60, now: date(6, 50))
        #expect(minutes == nil)
    }

    // MARK: - Seguridad

    @Test("Por defecto nunca se sugiere dormir menos de 7 horas")
    func defaultNeverSuggestsUnderSevenHours() {
        // 4 ciclos son 6 horas. Ofrecerlo como opción «limpia» sería recomendar
        // dormir por debajo del mínimo de la AASM para que cuadre una cuenta, y
        // ese es el daño concreto que este tipo de calculadora puede hacer.
        // El test está para que nadie lo reintroduzca sin verlo.
        let standard = SleepCycleCalculator(calendar: calendar)
        let options = standard.options(forWakeMinuteOfDay: 7 * 60, now: date(18, 0))

        let atLeastSevenHours = options.allSatisfy { $0.sleepMinutes >= 7 * 60 }
        let cycles: [Int] = options.map { $0.cycles }
        let expectedCycles: [Int] = [6, 5]

        #expect(options.count == 2)
        #expect(atLeastSevenHours)
        #expect(cycles == expectedCycles)
    }

    // MARK: - Parámetros

    @Test("Cambiar la duración del ciclo mueve todas las horas")
    func cycleLengthIsAParameter() {
        // La duración del ciclo es una media poblacional, no una constante de la
        // naturaleza: el tipo tiene que admitir otro valor sin tocar el cálculo.
        var custom = calculator
        custom.cycleMinutes = 100

        let options = custom.options(forWakeMinuteOfDay: 7 * 60, now: date(18, 0))
        // 5 ciclos × 100 min = 8 h 20, más 15 de latencia → 22:25
        #expect(text(options[1].bedtime) == "14 22:25")
        #expect(options[1].sleepMinutes == 500)
    }

    @Test("Sin latencia, acostarse y dormirse coinciden")
    func zeroLatency() {
        var custom = calculator
        custom.latencyMinutes = 0

        let options = custom.options(forWakeMinuteOfDay: 7 * 60, now: date(18, 0))
        #expect(text(options[0].bedtime) == "14 22:00")
    }
}
