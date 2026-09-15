import Foundation
import Testing

@testable import Crono

/// Pruebas de las vueltas de una alarma insistente y del método de desarme.
@Suite("Alarma insistente")
struct InsistenceCalculatorTests {

    // MARK: - Las vueltas

    @Test("Cuatro vueltas cada tres minutos")
    func defaultPlan() {
        let followUps = InsistenceCalculator.followUps(
            after: 7 * 60,
            schedule: .weekdays,
            plan: .default
        )

        let minutes = followUps.map(\.minuteOfDay)
        #expect(minutes == [7 * 60 + 3, 7 * 60 + 6, 7 * 60 + 9, 7 * 60 + 12])

        let ordinals = followUps.map(\.ordinal)
        #expect(ordinals == [1, 2, 3, 4])

        // Sin cruzar medianoche, los días son los mismos.
        let schedules = followUps.map(\.schedule)
        let allWeekdays = schedules.allSatisfy { $0 == WeekdaySet.weekdays }
        #expect(allWeekdays)
    }

    @Test("Sin plan no hay vueltas")
    func noPlanNoFollowUps() {
        let followUps = InsistenceCalculator.followUps(
            after: 7 * 60,
            schedule: .everyDay,
            plan: .none
        )
        #expect(followUps.isEmpty)
    }

    @Test("Una alarma sin días no tiene de qué volver")
    func emptyScheduleNoFollowUps() {
        // El formulario deja guardarla, pero no se registra en el sistema: sus
        // vueltas tampoco deben.
        let followUps = InsistenceCalculator.followUps(
            after: 7 * 60,
            schedule: [],
            plan: .default
        )
        #expect(followUps.isEmpty)
    }

    // MARK: - La medianoche

    @Test("Al cruzar medianoche la vuelta cambia de día de la semana")
    func crossingMidnightShiftsWeekdays() {
        // 23:58 de lunes a viernes, vueltas cada 3 minutos.
        let followUps = InsistenceCalculator.followUps(
            after: 23 * 60 + 58,
            schedule: .weekdays,
            plan: InsistencePlan(intervalMinutes: 3, repeats: 2)
        )

        let minutes = followUps.map(\.minuteOfDay)
        #expect(minutes == [1, 4])

        // Las dos caen ya en el día siguiente: de martes a sábado, no de lunes
        // a viernes. Con los días de la original sonarían 24 horas antes.
        let expected: WeekdaySet = [.tuesday, .wednesday, .thursday, .friday, .saturday]
        let schedules = followUps.map(\.schedule)
        #expect(schedules == [expected, expected])
    }

    @Test("Una vuelta antes de medianoche y otra después no comparten días")
    func splitAcrossMidnight() {
        // Lunes a las 23:59, vueltas cada minuto: caen a las 00:00 y a las
        // 00:01, ya del martes. El caso justo en la medianoche es el que más
        // fácil se escapa.
        let followUps = InsistenceCalculator.followUps(
            after: 23 * 60 + 59,
            schedule: .monday,
            plan: InsistencePlan(intervalMinutes: 1, repeats: 2)
        )

        let minutes = followUps.map(\.minuteOfDay)
        #expect(minutes == [0, 1])

        let schedules = followUps.map(\.schedule)
        let expected: [WeekdaySet] = [.tuesday, .tuesday]
        #expect(schedules == expected)
    }

    @Test("El sábado da la vuelta al domingo")
    func saturdayWrapsToSunday() {
        #expect(WeekdaySet.saturday.shiftedByOneDay() == WeekdaySet.sunday)
        #expect(WeekdaySet.sunday.shiftedByOneDay() == WeekdaySet.monday)
        #expect(WeekdaySet.everyDay.shiftedByOneDay() == WeekdaySet.everyDay)

        let weekendShifted: WeekdaySet = [.sunday, .monday]
        #expect(WeekdaySet.weekend.shiftedByOneDay() == weekendShifted)

        // El vacío se queda vacío: una alarma sin días tampoco tiene vueltas.
        let empty = WeekdaySet([])
        #expect(empty.shiftedByOneDay() == empty)
    }

    // MARK: - El margen

    @Test("El margen es lo que se le enseña al usuario")
    func totalSpan() {
        #expect(InsistenceCalculator.totalSpanMinutes(.default) == 12)
        #expect(InsistenceCalculator.totalSpanMinutes(.none) == 0)
        // Un plan a medias tampoco insiste.
        #expect(InsistenceCalculator.totalSpanMinutes(InsistencePlan(intervalMinutes: 5, repeats: 0)) == 0)
    }

    // MARK: - El método de desarme

    @Test("El método sobrevive al viaje por la base de datos")
    func disarmMethodRoundTrip() {
        let cases: [DisarmMethod] = [.stop, .arithmetic, .tag(uid: "04A2B3C4D5E6")]
        // El resultado del init opcional se ata fuera: comparar un opcional con
        // un miembro implícito dentro de la macro es la ambigüedad que ya costó
        // una ejecución en las reglas de repetición.
        for method in cases {
            let restored = DisarmMethod(rawValue: method.rawValue)
            #expect(restored == method)
        }
    }

    @Test("Una pegatina sin identificador no se acepta")
    func tagNeedsUID() {
        // Guardarla dejaría una alarma imposible de desarmar.
        #expect(DisarmMethod(rawValue: "tag:") == nil)
        #expect(DisarmMethod(rawValue: "loquesea") == nil)
    }

    @Test("Solo parar no pide nada; los otros dos sí")
    func requiresAction() {
        #expect(DisarmMethod.stop.requiresAction == false)
        #expect(DisarmMethod.arithmetic.requiresAction)
        #expect(DisarmMethod.tag(uid: "04A2").requiresAction)
    }
}
