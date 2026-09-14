import SwiftUI

/// La próxima alarma que va a sonar.
///
/// Cierra la pantalla Hoy porque cierra el día: lo de arriba es lo que queda por
/// hacer, y esto es a qué hora empieza el siguiente. Sin ella, la pestaña de
/// alarmas sería un compartimento estanco dentro de la propia app.
struct TodayNextAlarmCard: View {
    let alarm: AlarmItem
    let isRegistered: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "alarm")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.timeText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(isRegistered ? .secondary : .orange)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .groupedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Próxima alarma a las \(alarm.timeText), \(subtitle)")
    }

    private var subtitle: String {
        // Que una alarma activa no esté registrada en el sistema se dice también
        // aquí, no solo en su pestaña: si el usuario mira Hoy antes de acostarse,
        // esta es la línea que lee, y es donde importa enterarse.
        isRegistered
            ? "\(alarm.displayLabel) · \(alarm.scheduleText)"
            : "\(alarm.displayLabel) · no registrada, no sonará"
    }
}
