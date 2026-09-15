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

    var isActive: Bool { intervalMinutes > 0 && repeats > 0 }
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

    /// Las vueltas de una alarma, en orden.
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
