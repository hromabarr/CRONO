import SwiftUI

/// Tarjeta de cabecera de la pantalla Hoy: anillo de progreso y estado del día.
struct TodayHeaderView: View {
    var progress: TodayViewModel.DayProgress
    var headline: String
    var detail: String

    var body: some View {
        HStack(spacing: 22) {
            ProgressRingLabelView(
                fraction: progress.fraction,
                percentText: progress.percentText,
                countText: progress.countText
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .groupedCard(cornerRadius: 22)
        // El anillo se oculta a VoiceOver y el texto lo sustituye: leer "anillo
        // al 40 %" y luego "2 de 5" sería redundante.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(headline). \(progress.countText) completados. \(detail)")
    }
}

#Preview("Estados del día", traits: .sizeThatFitsLayout) {
    VStack(spacing: 14) {
        TodayHeaderView(
            progress: .init(completed: 0, total: 5),
            headline: "Empieza el día",
            detail: "Tienes 5 hábitos programados para hoy."
        )
        TodayHeaderView(
            progress: .init(completed: 2, total: 5),
            headline: "Vas por buen camino",
            detail: "Te quedan 3 hábitos por marcar."
        )
        TodayHeaderView(
            progress: .init(completed: 5, total: 5),
            headline: "Día completo",
            detail: "Los 5 hábitos de hoy, hechos."
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
