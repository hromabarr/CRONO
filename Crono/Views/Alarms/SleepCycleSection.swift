import SwiftUI

/// Sección del formulario de alarma con las horas sugeridas para acostarse.
///
/// ## Sobre la redacción
///
/// Los textos están medidos contra lo que la evidencia respalda. No prometen un
/// despertar mejor, no dicen «basado en la ciencia del sueño» y no hablan de
/// fases —la app no mide nada—. Dicen que la cifra es orientativa y que dormir
/// suficiente importa más que cuadrar la cuenta, que es lo que las guías del
/// sueño sí sostienen.
struct SleepCycleSection: View {
    private let wakeMinuteOfDay: Int
    private let now: Date
    private let calculator: SleepCycleCalculator

    init(
        wakeMinuteOfDay: Int,
        now: Date = .now,
        calculator: SleepCycleCalculator = SleepCycleCalculator()
    ) {
        self.wakeMinuteOfDay = wakeMinuteOfDay
        self.now = now
        self.calculator = calculator
    }

    var body: some View {
        Section {
            ForEach(options) { option in
                SleepOptionRow(option: option)
            }
            goingToBedNowRow
        } header: {
            Text("Para despertar a las \(ClockTime.text(minuteOfDay: wakeMinuteOfDay))")
        } footer: {
            Text(caveat)
        }
    }

    // MARK: - Contenido

    private var options: [SleepOption] {
        calculator.options(forWakeMinuteOfDay: wakeMinuteOfDay, now: now)
    }

    /// Cuánto se dormiría acostándose en este momento.
    ///
    /// Es el ancla del «ahora» que hace útil el resto: sin ella, a las tres de la
    /// madrugada la sección sería una lista de horas tachadas sin decir qué hacer.
    @ViewBuilder
    private var goingToBedNowRow: some View {
        if let minutes = calculator.sleepMinutesIfGoingToBedNow(
            wakeMinuteOfDay: wakeMinuteOfDay,
            now: now
        ) {
            HStack {
                Text("Si te acuestas ahora")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(ClockTime.duration(minutes: minutes))
                    .monospacedDigit()
                    .foregroundStyle(minutes < Self.recommendedMinimumMinutes ? .orange : .secondary)
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
        }
    }

    /// Mínimo recomendado por la AASM para adultos: 7 horas.
    private static let recommendedMinimumMinutes = 7 * 60

    private var caveat: String {
        """
        Los ciclos duran unos 90 minutos de media, pero varían entre 70 y 120 \
        según la persona y la noche, así que estas horas son orientativas. \
        Dormir lo suficiente importa más que cuadrar ciclos: la recomendación \
        para adultos es de 7 horas o más.
        """
    }
}

// MARK: - Fila

private struct SleepOptionRow: View {
    let option: SleepOption

    var body: some View {
        HStack(spacing: 12) {
            Text(ClockTime.text(from: option.bedtime))
                // La hora es el dato que se busca de un vistazo. Cifras de ancho
                // fijo para que las dos filas queden alineadas en columna.
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(option.isPast ? .secondary : .primary)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(option.durationText)
                    .font(.subheadline)
                    .foregroundStyle(option.isPast ? .tertiary : .secondary)

                Text(cyclesText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        // Las pasadas se atenúan pero no se ocultan: saber que se te escapó la de
        // nueve horas es información, y quitarlas dejaría la sección medio vacía
        // sin explicar por qué.
        .opacity(option.isPast ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cyclesText: String {
        option.cycles == 1 ? "1 ciclo" : "\(option.cycles) ciclos"
    }

    private var accessibilityLabel: String {
        let time = ClockTime.text(from: option.bedtime)
        let base = "Acostarse a las \(time), \(option.durationText), \(cyclesText)"
        return option.isPast ? "\(base). Esta hora ya pasó." : base
    }
}

#Preview("Ciclos de sueño") {
    // 22:00: la de 9 h (21:45) ya pasó, la de 7 h 30 (23:15) no.
    let now = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 14, hour: 22, minute: 0)
    ) ?? .now

    Form {
        SleepCycleSection(wakeMinuteOfDay: 7 * 60, now: now)
    }
}
