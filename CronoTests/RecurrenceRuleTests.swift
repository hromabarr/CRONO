import Foundation
import Testing

@testable import Crono

/// Pruebas del siguiente vencimiento de una tarea recurrente.
///
/// Calendario en UTC y fechas fijas: casi todos los casos cruzan un límite de
/// mes o de año, que es donde la aritmética de fechas se rompe.
@Suite("Repetición de tareas")
struct RecurrenceRuleTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func next(_ rule: RecurrenceRule, after dayKey: DayKey) -> DayKey? {
        rule.nextDueDayKey(after: dayKey, calendar: calendar)
    }

    // MARK: - Diaria

    @Test("Cada día avanza uno, cruzando meses y años")
    func daily() {
        #expect(next(.daily, after: 20_260_914) == 20_260_915)
        #expect(next(.daily, after: 20_260_930) == 20_261_001)
        #expect(next(.daily, after: 20_261_231) == 20_270_101)
    }

    // MARK: - Semanal

    @Test("Semanal salta al siguiente día marcado")
    func weeklyJumpsToNextMarkedDay() {
        // 14/09/2026 es lunes. Con lunes, miércoles y viernes marcados, desde el
        // lunes toca el miércoles 16.
        let mwf: WeekdaySet = [.monday, .wednesday, .friday]
        #expect(next(.weekly(mwf), after: 20_260_914) == 20_260_916)
        #expect(next(.weekly(mwf), after: 20_260_916) == 20_260_918)
        // Y desde el viernes 18 vuelve al lunes 21, cruzando el fin de semana.
        #expect(next(.weekly(mwf), after: 20_260_918) == 20_260_921)
    }

    @Test("Semanal con un solo día da la vuelta completa")
    func weeklySingleDay() {
        // Solo lunes: desde el lunes 14, el siguiente es el 21.
        #expect(next(.weekly([.monday]), after: 20_260_914) == 20_260_921)
    }

    @Test("Semanal con todos los días equivale a diaria")
    func weeklyEveryDay() {
        #expect(next(.weekly(.everyDay), after: 20_260_914) == 20_260_915)
    }

    @Test("Semanal sin días no produce siguiente")
    func weeklyWithoutDays() {
        // El formulario no deja guardarlo, pero un dato corrupto no debe
        // provocar un bucle ni una fecha inventada.
        #expect(next(.weekly([]), after: 20_260_914) == nil)
    }

    // MARK: - Mensual

    @Test("Mensual mantiene el día del mes")
    func monthlyKeepsDayOfMonth() {
        #expect(next(.monthly, after: 20_260_914) == 20_261_014)
        #expect(next(.monthly, after: 20_261_215) == 20_270_115)
    }

    @Test("Mensual recorta cuando el día no existe en el mes siguiente")
    func monthlyClampsToLastDay() {
        // Del 31 de enero al 28 de febrero, no al 3 de marzo.
        //
        // Recortar es lo correcto: saltarse febrero dejaría de ser mensual, y
        // desbordar al 3 de marzo movería la tarea a un mes que no le tocaba.
        #expect(next(.monthly, after: 20_260_131) == 20_260_228)
        // 2028 es bisiesto, así que ahí cae el 29.
        #expect(next(.monthly, after: 20_280_131) == 20_280_229)
        // Y del 31 de marzo al 30 de abril.
        #expect(next(.monthly, after: 20_260_331) == 20_260_430)
    }

    // MARK: - Anual

    @Test("Anual mantiene día y mes")
    func yearlyKeepsDayAndMonth() {
        #expect(next(.yearly, after: 20_260_914) == 20_270_914)
    }

    @Test("Anual recorta el 29 de febrero en año no bisiesto")
    func yearlyClampsLeapDay() {
        // 2028 es bisiesto; 2029 no.
        #expect(next(.yearly, after: 20_280_229) == 20_290_228)
    }

    // MARK: - Persistencia

    @Test("La regla sobrevive al viaje por la base de datos")
    func roundTrip() {
        let weekly = RecurrenceRule.weekly([.monday, .wednesday, .friday])
        // La máscara viaja dentro de la cadena: 2 + 8 + 32 = 42.
        #expect(weekly.rawValue == "weekly:42")

        let restored = RecurrenceRule(rawValue: weekly.rawValue)
        #expect(restored?.rawValue == weekly.rawValue)
        #expect(next(restored!, after: 20_260_914) == 20_260_916)
    }
}
