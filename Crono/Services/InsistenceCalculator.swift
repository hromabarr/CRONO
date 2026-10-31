import Foundation

/// Cada cuánto vuelve una alarma y cuántas veces, mientras no se desarme.
struct InsistencePlan: Equatable, Sendable {
    /// Minutos entre una vuelta y la siguiente.
    var intervalMinutes: Int

    /// Cuántas veces vuelve. No incluye la alarma original.
    var repeats: Int

    /// Sin insistencia: la alarma suena una vez y ya está.
    static let none = InsistencePlan(intervalMinutes: 0, repeats: 0)

    /// Cuatro vueltas cada tres minutos: doce minutos de margen.
    ///
    /// El techo existe a propósito. Una alarma que volviera indefinidamente
    /// acabaría sonando en una reunión con el teléfono olvidado en casa, y eso
    /// no despierta a nadie: solo enseña a desactivar la app.
    static let `default` = InsistencePlan(intervalMinutes: 3, repeats: 4)

    /// Cada minuto, hasta que se desarme.
    ///
    /// «Hasta que se desarme» con un techo de una hora, que es lo más cerca de
    /// «sin parar» que permite iOS: el botón Parar existe siempre y ninguna app
    /// puede quitarlo, así que lo que se hace es que pararla no sirva de nada
    /// más que un minuto. El techo sigue estando por lo mismo que el del plan
    /// por defecto, pero una hora sonando cada minuto no la aguanta nadie
    /// dormido.
    static let untilDisarmed = InsistencePlan(intervalMinutes: 1, repeats: 60)

    var isActive: Bool { intervalMinutes > 0 && repeats > 0 }

    var isUntilDisarmed: Bool { self == .untilDisarmed }
}

/// Una vuelta de la alarma principal, ya resuelta a hora y días.
struct FollowUpAlarm: Equatable, Sendable {
    /// Minutos desde medianoche.
    let minuteOfDay: Int

    /// Los días en que suena **esta** vuelta, que no siempre son los de la
    /// alarma original: ver `InsistenceCalculator`.
    let schedule: WeekdaySet

    /// Cuál es, empezando por 1.
    let ordinal: Int
}

/// Calcula las vueltas de una alarma insistente.
///
/// ## Por qué las vueltas se programan por adelantado
///
/// Lo natural sería programar la siguiente cuando el usuario pulsa Parar.
/// AlarmKit deja poner un `stopIntent` propio en ese botón, pero **no garantiza
/// ejecutarlo**: si la alarma suena con la pantalla ya desbloqueada y el usuario
/// actúa ahí, la alarma se para y el intent no corre. Colgar la insistencia de
/// ese evento sería construirla sobre lo único que falla justo cuando hace
/// falta.
///
/// Así que se registran todas de golpe al armar la alarma, y se cancelan cuando
/// el usuario desarma. El `stopIntent` queda como atajo para abrir la pantalla
/// de desarme, no como el mecanismo.
///
/// ## El detalle de la medianoche
///
/// Una alarma de días laborables a las 23:58, con vueltas cada tres minutos,
/// suena a las 00:01, 00:04… y esas ya no son de lunes a viernes sino de martes
/// a sábado. Programarlas con los días de la original las adelantaría 24 horas
/// justas: sonarían la madrugada equivocada.
enum InsistenceCalculator {

    /// Las vueltas de una alarma, en orden, como horas de reloj semanales.
    ///
    /// Es la forma de enseñarlas («7:03, 7:06…»). Para registrarlas en el
    /// sistema se usan fechas fijas: ver `occurrencesAhead`.
    ///
    /// Devuelve vacío si el plan no insiste o si la alarma no tiene días —una
    /// alarma que no suena no tiene de qué volver—.
    static func followUps(
        after minuteOfDay: Int,
        schedule: WeekdaySet,
        plan: InsistencePlan
    ) -> [FollowUpAlarm] {
        guard plan.isActive, !schedule.isEmpty else { return [] }

        let minutesPerDay = 24 * 60
        var result: [FollowUpAlarm] = []

        for ordinal in 1...plan.repeats {
            let raw = minuteOfDay + ordinal * plan.intervalMinutes

            // Cuántas medianoches cruza. Con los planes razonables es 0 o 1,
            // pero el bucle no depende de eso.
            let daysCrossed = raw / minutesPerDay
            var shifted = schedule
            for _ in 0..<daysCrossed {
                shifted = shifted.shiftedByOneDay()
            }

            result.append(
                FollowUpAlarm(
                    minuteOfDay: raw % minutesPerDay,
                    schedule: shifted,
                    ordinal: ordinal
                )
            )
        }

        return result
    }

    /// Cuánto margen da el plan, en minutos, desde que suena hasta la última
    /// vuelta.
    ///
    /// Es lo que hay que enseñarle al usuario al elegir: «cada 3 minutos, 4
    /// veces» no dice nada; «te insistirá durante 12 minutos», sí.
    static func totalSpanMinutes(_ plan: InsistencePlan) -> Int {
        plan.isActive ? plan.intervalMinutes * plan.repeats : 0
    }
}

// MARK: - Vueltas con fecha

/// Una vuelta ya registrada en el sistema, con la fecha exacta en que suena.
struct ScheduledFollowUp: Equatable, Sendable {
    /// Con qué identificador quedó registrada, para poder cancelarla.
    let systemID: UUID

    /// Cuándo sonó —o sonará— la alarma principal de la que es vuelta.
    ///
    /// Es lo que agrupa las vueltas de una misma mañana: desarmar cancela las de
    /// esta mañana y deja intactas las de mañana.
    let occurrence: Date

    let fireDate: Date
}

extension InsistenceCalculator {

    /// Cuántas mañanas por delante quedan registradas.
    ///
    /// ## Por qué fechas fijas y no una repetición semanal
    ///
    /// Una vuelta semanal «lunes a viernes a las 7:03» no se puede cancelar solo
    /// para hoy: cancelarla la quita de todos los días. Y desarmar tiene que
    /// callar esta mañana sin apagar la insistencia de la siguiente.
    ///
    /// Así que cada vuelta es una alarma de fecha fija, y se registran las de
    /// unas pocas mañanas por delante. Se rellenan cada vez que se abre la app y
    /// al desarmar, que exige abrirla; tres mañanas cubren un fin de semana sin
    /// tocar el teléfono. Si pasan más días sin abrirla, la alarma principal
    /// sigue sonando igual: lo que se pierde es solo la insistencia.
    ///
    /// Con planes largos se registran menos mañanas, para no pasar de
    /// `maxRegisteredFollowUps`: sesenta vueltas por tres mañanas serían 180
    /// alarmas del sistema por una sola alarma nuestra. Con una mañana basta
    /// igual, porque desarmar obliga a abrir la app y eso registra la
    /// siguiente.
    static func occurrencesAhead(for plan: InsistencePlan) -> Int {
        guard plan.repeats > 0 else { return 0 }
        return max(1, min(3, maxRegisteredFollowUps / plan.repeats))
    }

    /// Cuántas vueltas como mucho se dejan registradas a la vez por alarma.
    static let maxRegisteredFollowUps = 64

    /// Las próximas veces que suena una alarma, a partir de `start` incluido.
    ///
    /// Recorre días en lugar de sumar minutos: el día del cambio de hora,
    /// «las 7:00» no está a 24 horas de las 7:00 del día anterior.
    static func occurrences(
        minuteOfDay: Int,
        schedule: WeekdaySet,
        from start: Date,
        count: Int,
        calendar: Calendar = AppCalendar.current
    ) -> [Date] {
        guard !schedule.isEmpty, count > 0 else { return [] }

        let firstDay = calendar.startOfDay(for: start)
        var result: [Date] = []

        // Con al menos un día marcado, una semana y un día bastan para encontrar
        // cada ocurrencia; el tope evita un bucle infinito si algo falla.
        for offset in 0..<(8 * count) {
            guard result.count < count,
                  let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  schedule.contains(weekday: calendar.component(.weekday, from: day)),
                  let date = calendar.date(
                      bySettingHour: minuteOfDay / 60,
                      minute: minuteOfDay % 60,
                      second: 0,
                      of: day
                  ),
                  date >= start
            else { continue }
            result.append(date)
        }

        return result
    }

    /// Cuándo suenan las vueltas de una ocurrencia, en orden.
    ///
    /// Se suma tiempo y no hora de reloj, a propósito: «tres minutos después»
    /// son tres minutos aunque en medio cambie la hora. Y cruzar medianoche no
    /// necesita nada especial, porque una fecha ya sabe qué día es.
    static func fireDates(after occurrence: Date, plan: InsistencePlan) -> [Date] {
        guard plan.isActive else { return [] }
        return (1...plan.repeats).map { ordinal in
            occurrence.addingTimeInterval(TimeInterval(ordinal * plan.intervalMinutes * 60))
        }
    }
}
