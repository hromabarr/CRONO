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
        let cases: [DisarmMethod] = [.stop, .arithmetic, .scannedCode(value: "8414533043")]
        for method in cases {
            let restored = DisarmMethod(rawValue: method.rawValue)
            #expect(restored == method)
        }
    }

    @Test("Un código con dos puntos dentro sigue viajando entero")
    func codeWithColonSurvives() {
        // El contenido de un QR puede ser una URL, y ahí los dos puntos son
        // parte del dato. Cortar por el primero partiría el código en dos.
        let method = DisarmMethod.scannedCode(value: "crono://desarmar/ABC:123")
        let restored = DisarmMethod(rawValue: method.rawValue)
        #expect(restored == method)
    }

    @Test("Un código vacío no se acepta")
    func codeNeedsValue() {
        // Guardarlo dejaría una alarma imposible de desarmar.
        #expect(DisarmMethod(rawValue: "code:") == nil)
        #expect(DisarmMethod(rawValue: "loquesea") == nil)
    }

    @Test("Solo parar no pide nada; los otros dos sí")
    func requiresAction() {
        #expect(DisarmMethod.stop.requiresAction == false)
        #expect(DisarmMethod.arithmetic.requiresAction)
        #expect(DisarmMethod.scannedCode(value: "8414533043").requiresAction)
    }

    // MARK: - El código que desarma

    @Test("El secreto generado no lleva caracteres que se confundan al leerlos")
    func secretAvoidsAmbiguousCharacters() {
        let secret = DisarmCode.makeSecret()
        #expect(secret.count == DisarmCode.secretLength)

        // Acaba impreso en un papel que alguien puede tener que teclear si algo
        // falla, así que fuera el cero y la O, el uno y la I y la ele.
        let ambiguous: Set<Character> = ["0", "O", "1", "I", "L"]
        let hasAmbiguous = secret.contains { ambiguous.contains($0) }
        #expect(hasAmbiguous == false)
    }

    @Test("Dos secretos seguidos no son el mismo")
    func secretsDiffer() {
        #expect(DisarmCode.makeSecret() != DisarmCode.makeSecret())
    }

    @Test("Escanear el código guardado desarma")
    func matchingCodeDisarms() {
        let method = DisarmMethod.scannedCode(value: "8414533043")
        #expect(DisarmCode.matches("8414533043", method: method))
        // Algunos lectores añaden un salto de línea al final.
        #expect(DisarmCode.matches(" 8414533043\n", method: method))
    }

    @Test("Escanear otra cosa no desarma")
    func wrongCodeDoesNotDisarm() {
        let method = DisarmMethod.scannedCode(value: "8414533043")
        #expect(DisarmCode.matches("8414533044", method: method) == false)
        #expect(DisarmCode.matches("", method: method) == false)
        #expect(DisarmCode.matches("   ", method: method) == false)

        // Sin tocar mayúsculas: normalizar de más acerca códigos distintos, y un
        // falso positivo aquí desarma la alarma con el bote equivocado.
        let letters = DisarmMethod.scannedCode(value: "ABC123")
        #expect(DisarmCode.matches("abc123", method: letters) == false)
    }

    @Test("La cámara no desarma una alarma que no se desarma con código")
    func cameraDoesNotDisarmOtherMethods() {
        // Enfocar cualquier cosa no puede saltarse la cuenta.
        #expect(DisarmCode.matches("8414533043", method: .arithmetic) == false)
        #expect(DisarmCode.matches("8414533043", method: .stop) == false)
    }

    @Test("Un código en blanco no se puede registrar")
    func blankCodeIsNotUsable() {
        #expect(DisarmCode.isUsable("8414533043"))
        #expect(DisarmCode.isUsable("  \n ") == false)
        #expect(DisarmCode.method(for: "  \n ") == nil)

        let method = DisarmCode.method(for: "  8414533043 ")
        #expect(method == DisarmMethod.scannedCode(value: "8414533043"))
    }
}
