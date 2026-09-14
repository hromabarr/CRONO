import Foundation

/// Una opción de descanso: a qué hora acostarse para despertar a la hora fijada.
struct SleepOption: Identifiable, Equatable, Sendable {
    /// Número de ciclos completos de sueño.
    let cycles: Int

    /// Momento en que habría que meterse en la cama.
    let bedtime: Date

    /// Momento en que sonaría la alarma.
    let wakeTime: Date

    /// Minutos de sueño efectivo, sin contar el tiempo en dormirse.
    let sleepMinutes: Int

    /// La hora de acostarse ya pasó. Sigue en la lista, atenuada: saber que se
    /// te escapó la de nueve horas es información, y ocultarla dejaría la lista
    /// medio vacía sin explicar por qué.
    let isPast: Bool

    var id: Int { cycles }

    /// «7 h 30 min».
    var durationText: String {
        let hours = sleepMinutes / 60
        let minutes = sleepMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }
}

/// Calcula a qué hora conviene acostarse para despertar tras un número entero
/// de ciclos de sueño.
///
/// ## Qué respalda esto y qué no
///
/// Aritmética sencilla: hora de despertar − (ciclos × duración) − lo que se tarda
/// en dormirse. No mide nada, no observa al usuario y no sabe cómo duerme.
///
/// Conviene tener presente el estado de la evidencia, porque condiciona cómo se
/// puede presentar el resultado:
///
/// - Los ciclos existen, pero **90 minutos es una simplificación**. La mejor
///   medida disponible (Blume et al., *Sleep Health* 2023: 6.064 ciclos por
///   polisomnografía en 369 personas) da una mediana de **96 min**, con
///   variación grande entre personas y dentro de la misma noche, y con el primer
///   ciclo sistemáticamente más corto. El rango habitual es 70–120 min.
/// - **Ninguna sociedad del sueño recomienda dormir en múltiplos de ciclo.** La
///   AASM recomienda 7 h o más; la National Sleep Foundation, 7–9 h. Lo de «5 o
///   6 ciclos» es ingeniería inversa de esas cifras, no una recomendación.
/// - No hay ensayo que muestre que cuadrar ciclos mejore el despertar. El más
///   cercano (Campanella et al., *Clocks & Sleep* 2024, n=29) salió negativo.
///
/// Se mantiene el ciclo en 90 min porque es la convención que el usuario espera
/// y la que usan las demás apps; la diferencia con 96 queda muy dentro del ruido
/// del método. Es un parámetro, no una constante, precisamente por eso.
///
/// La consecuencia práctica: la cifra es **orientativa**, y la interfaz no debe
/// presentarla como precisa ni prometer un despertar mejor.
struct SleepCycleCalculator {

    /// Duración de un ciclo de sueño, en minutos.
    ///
    /// Media poblacional, no constante: los ciclos reales van de 70 a 120 min
    /// según la persona y la noche.
    var cycleMinutes: Int

    /// Lo que se tarda en dormirse desde que uno se acuesta.
    var latencyMinutes: Int

    /// Números de ciclos que se ofrecen, de más a menos descanso.
    ///
    /// Solo 6 y 5 —9 h y 7 h 30— por una razón de seguridad, no de diseño:
    /// 4 ciclos son 6 horas, y ofrecerlo como opción «limpia» sería recomendar
    /// dormir por debajo del mínimo de 7 h de la AASM. Una app no debe empujar a
    /// dormir menos para que cuadre una cuenta.
    var offeredCycles: [Int]

    var calendar: Calendar

    init(
        cycleMinutes: Int = 90,
        latencyMinutes: Int = 15,
        offeredCycles: [Int] = [6, 5],
        calendar: Calendar = AppCalendar.current
    ) {
        self.cycleMinutes = cycleMinutes
        self.latencyMinutes = latencyMinutes
        self.offeredCycles = offeredCycles
        self.calendar = calendar
    }

    // MARK: - Cálculo

    /// Opciones de acostarse para una alarma a `wakeMinuteOfDay`.
    ///
    /// `now` decide dos cosas: cuál es la próxima vez que sonará esa alarma, y
    /// cuáles de las opciones siguen siendo alcanzables.
    func options(forWakeMinuteOfDay wakeMinuteOfDay: Int, now: Date) -> [SleepOption] {
        guard let wakeTime = nextOccurrence(ofMinuteOfDay: wakeMinuteOfDay, after: now) else {
            return []
        }

        var result: [SleepOption] = []
        for cycles in offeredCycles {
            let sleepMinutes = cycles * cycleMinutes
            let totalMinutes = sleepMinutes + latencyMinutes

            guard let bedtime = calendar.date(byAdding: .minute, value: -totalMinutes, to: wakeTime)
            else { continue }

            result.append(
                SleepOption(
                    cycles: cycles,
                    bedtime: bedtime,
                    wakeTime: wakeTime,
                    sleepMinutes: sleepMinutes,
                    isPast: bedtime < now
                )
            )
        }
        return result
    }

    /// Cuánto se dormiría acostándose en este momento, en minutos.
    ///
    /// Existe para que la sección nunca quede en un callejón sin salida: cuando
    /// es tan tarde que ninguna opción de ciclo completo se alcanza, lo útil no
    /// es una lista tachada sino saber con qué te vas a levantar.
    ///
    /// Devuelve `nil` si la alarma sonaría antes de haberse dormido.
    func sleepMinutesIfGoingToBedNow(wakeMinuteOfDay: Int, now: Date) -> Int? {
        guard let wakeTime = nextOccurrence(ofMinuteOfDay: wakeMinuteOfDay, after: now),
              let asleepAt = calendar.date(byAdding: .minute, value: latencyMinutes, to: now),
              asleepAt < wakeTime,
              let minutes = calendar.dateComponents([.minute], from: asleepAt, to: wakeTime).minute
        else { return nil }

        return minutes
    }

    // MARK: - Auxiliares

    /// La próxima vez que el reloj marque esa hora del día, contando desde `now`.
    ///
    /// Si la hora ya pasó hoy, es mañana. Un despertador a las 7:00 consultado a
    /// las 23:00 se refiere al de mañana, no al que ya sonó.
    func nextOccurrence(ofMinuteOfDay minuteOfDay: Int, after now: Date) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        guard let todayAtTime = calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfToday)
        else { return nil }

        if todayAtTime > now { return todayAtTime }
        return calendar.date(byAdding: .day, value: 1, to: todayAtTime)
    }

    /// Minutos desde medianoche de un instante.
    func minuteOfDay(of date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
