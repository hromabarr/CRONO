import Foundation
import Testing

@testable import HabitTracker

/// Pruebas de los cimientos: conversión de fechas y máscara de días.
///
/// Son tipos pequeños, pero los usa todo lo demás: un error de un bit en
/// `WeekdaySet` o un desfase de un día en `DayKey` se propaga a las rachas, al
/// calendario y a la vista Hoy a la vez.
@Suite("Claves de día y días de la semana")
struct DayKeyTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts)!
    }

    // MARK: - Conversión

    @Test("Una fecha se convierte en yyyyMMdd")
    func dateToDayKey() {
        #expect(calendar.dayKey(from: date(2026, 7, 27)) == 20_260_727)
        #expect(calendar.dayKey(from: date(2026, 1, 1)) == 20_260_101)
        #expect(calendar.dayKey(from: date(1999, 12, 31)) == 19_991_231)
    }

    @Test("La conversión es reversible")
    func roundTrip() {
        let original = 20_260_727
        let recovered = calendar.date(fromDayKey: original)
        #expect(recovered != nil)
        #expect(calendar.dayKey(from: recovered!) == original)
    }

    @Test("La hora del día no altera la clave")
    func timeOfDayIsIrrelevant() {
        var early = DateComponents()
        early.year = 2026; early.month = 7; early.day = 27
        early.hour = 0; early.minute = 1

        var late = DateComponents()
        late.year = 2026; late.month = 7; late.day = 27
        late.hour = 23; late.minute = 59

        #expect(
            calendar.dayKey(from: calendar.date(from: early)!)
                == calendar.dayKey(from: calendar.date(from: late)!)
        )
    }

    @Test("Una clave imposible no produce fecha")
    func invalidKeyReturnsNil() {
        // 30 de febrero: el calendario lo normalizaría al 2 de marzo si no se
        // comprobara, y una fecha silenciosamente desplazada es peor que nil.
        #expect(calendar.date(fromDayKey: 20_260_230) == nil)
        #expect(calendar.dayKey(in: MonthIdentifier(year: 2026, month: 2), day: 30) == nil)
    }

    // MARK: - Aritmética

    @Test("Desplazar días cruza meses y años")
    func offsetCrossesBoundaries() {
        // Restar 1 al entero daría 20260700, que no existe.
        #expect(calendar.dayKey(20_260_701, offsetByDays: -1) == 20_260_630)
        #expect(calendar.dayKey(20_260_101, offsetByDays: -1) == 20_251_231)
        #expect(calendar.dayKey(20_251_231, offsetByDays: 1) == 20_260_101)
    }

    @Test("Febrero de un año bisiesto tiene 29 días")
    func leapYear() {
        #expect(calendar.dayKey(20_240_228, offsetByDays: 1) == 20_240_229)
        #expect(calendar.numberOfDays(in: MonthIdentifier(year: 2024, month: 2)) == 29)
        #expect(calendar.numberOfDays(in: MonthIdentifier(year: 2026, month: 2)) == 28)
    }

    @Test("El intervalo de claves es inclusivo y ordenado")
    func dayKeyRange() {
        let keys = calendar.dayKeys(from: 20_260_628, to: 20_260_702)
        #expect(keys == [20_260_628, 20_260_629, 20_260_630, 20_260_701, 20_260_702])

        // Un intervalo invertido está vacío, no infinito.
        #expect(calendar.dayKeys(from: 20_260_702, to: 20_260_628).isEmpty)
    }

    // MARK: - Máscara de días

    @Test("Cada día ocupa su bit")
    func weekdayBits() {
        #expect(WeekdaySet(weekday: 1) == .sunday)
        #expect(WeekdaySet(weekday: 2) == .monday)
        #expect(WeekdaySet(weekday: 7) == .saturday)
        #expect(WeekdaySet.everyDay.rawValue == 127)
        #expect(WeekdaySet.everyDay.dayCount == 7)
        #expect(WeekdaySet.weekdays.dayCount == 5)
        #expect(WeekdaySet.weekend.dayCount == 2)
    }

    @Test("«Diario» es la máscara completa, no un caso aparte")
    func dailyIsJustEveryBit() {
        let allSeven: WeekdaySet = [
            .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday
        ]
        #expect(allSeven == .everyDay)
        #expect(allSeven.isEveryDay)
        #expect(WeekdaySet.weekdays.isEveryDay == false)
    }

    @Test("La consulta por día respeta la convención de Foundation")
    func containsWeekday() {
        let workdays = WeekdaySet.weekdays
        #expect(workdays.contains(weekday: 2))   // lunes
        #expect(workdays.contains(weekday: 6))   // viernes
        #expect(workdays.contains(weekday: 7) == false)  // sábado
        #expect(workdays.contains(weekday: 1) == false)  // domingo
    }

    @Test("Un día fuera de rango no rompe la máscara")
    func outOfRangeWeekdayIsIgnored() {
        #expect(WeekdaySet.everyDay.contains(weekday: 0) == false)
        #expect(WeekdaySet.everyDay.contains(weekday: 8) == false)
        #expect(WeekdaySet(weekday: 99).isEmpty)
        // Bits basura de un dato corrupto se descartan al construir.
        #expect(WeekdaySet(rawValue: 0b1111_1111_1111) == .everyDay)
    }

    @Test("Alternar un día lo añade y lo quita")
    func togglingWeekday() {
        let start: WeekdaySet = [.monday]
        let added = start.toggling(weekday: 4)
        #expect(added == [.monday, .wednesday])
        #expect(added.toggling(weekday: 4) == start)
    }

    @Test("El orden de presentación empieza por el día del usuario")
    func orderedWeekdays() {
        // WeekdaySet.weekdayOrder usa AppCalendar.current, así que solo se
        // comprueba la propiedad estructural: siete días sin repetir.
        let order = WeekdaySet.weekdayOrder
        #expect(order.count == 7)
        #expect(Set(order) == Set(1...7))

        // Los días seleccionados salen en el orden de presentación, no por bit.
        let selected = WeekdaySet.weekdays.orderedWeekdays
        #expect(selected.count == 5)
        #expect(Set(selected) == Set([2, 3, 4, 5, 6]))
    }

    // MARK: - Meses

    @Test("El mes se deriva de la clave de día")
    func monthFromDayKey() {
        #expect(calendar.monthIdentifier(from: 20_260_727) == MonthIdentifier(year: 2026, month: 7))
    }

    @Test("Desplazar meses cruza el año")
    func monthOffset() {
        let december = MonthIdentifier(year: 2025, month: 12)
        #expect(calendar.month(december, offsetByMonths: 1) == MonthIdentifier(year: 2026, month: 1))
        #expect(calendar.month(december, offsetByMonths: -12) == MonthIdentifier(year: 2024, month: 12))
    }

    @Test("Los meses se ordenan cronológicamente")
    func monthOrdering() {
        #expect(MonthIdentifier(year: 2025, month: 12) < MonthIdentifier(year: 2026, month: 1))
        #expect(MonthIdentifier(year: 2026, month: 3) < MonthIdentifier(year: 2026, month: 11))
    }
}
