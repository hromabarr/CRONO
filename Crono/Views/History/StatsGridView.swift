import SwiftUI

/// Las tres cifras de cabecera del historial.
struct StatsGridView: View {
    var stats: HabitStats
    /// Nombre del mes al que se refiere el porcentaje, para que la etiqueta
    /// diga de qué periodo habla en lugar de un vago "completado".
    var monthName: String

    var body: some View {
        HStack(spacing: 10) {
            StatTile(
                value: "\(stats.currentStreak)",
                caption: "Racha actual",
                accessibilityText: streakDescription(stats.currentStreak, prefix: "Racha actual")
            )
            StatTile(
                value: "\(stats.bestStreak)",
                caption: "Mejor racha",
                accessibilityText: streakDescription(stats.bestStreak, prefix: "Mejor racha")
            )
            StatTile(
                value: "\(Int((stats.completionRate * 100).rounded()))%",
                caption: monthName.capitalized,
                accessibilityText:
                    "\(Int((stats.completionRate * 100).rounded()))% completado en \(monthName)"
            )
        }
    }

    private func streakDescription(_ value: Int, prefix: String) -> String {
        value == 1 ? "\(prefix): 1 día" : "\(prefix): \(value) días"
    }
}

/// Una cifra con su etiqueta.
struct StatTile: View {
    var value: String
    var caption: String
    var accessibilityText: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .groupedCard(cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// Fila con la racha actual de un hábito concreto.
struct HabitStreakRow: View {
    var habit: Habit
    var streak: Int

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(habit.color.color)
                .frame(width: 12, height: 12)

            Text(habit.name)
                .font(.body)

            Spacer(minLength: 8)

            Label {
                Text(streak == 1 ? "1 día" : "\(streak) días")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            streak == 1
                ? "\(habit.name), racha de 1 día"
                : "\(habit.name), racha de \(streak) días"
        )
    }
}

#Preview("Estadísticas", traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        StatsGridView(
            stats: HabitStats(currentStreak: 12, bestStreak: 21, completionRate: 0.84),
            monthName: "julio"
        )
        StatsGridView(
            stats: .zero,
            monthName: "julio"
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
