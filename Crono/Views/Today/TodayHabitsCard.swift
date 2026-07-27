import SwiftUI

/// Tarjeta con los hábitos de hoy y sus separadores.
struct TodayHabitsCard: View {
    let viewModel: TodayViewModel
    let habits: [Habit]
    let onToggle: (Habit) -> Void

    /// Fila ya resuelta: se sabe de antemano si lleva separador delante.
    struct Row: Identifiable {
        let habit: Habit
        let showsDivider: Bool

        var id: UUID { habit.uuid }
    }

    /// Se construye con un bucle y no con `enumerated().map { i, x in ... }`:
    /// ese cierre recibe una tupla con etiquetas que hay que desestructurar, y
    /// es trabajo de inferencia gratuito para algo que un bucle hace sin ambigüedad.
    private var rows: [Row] {
        var result: [Row] = []
        result.reserveCapacity(habits.count)
        for habit in habits {
            result.append(Row(habit: habit, showsDivider: !result.isEmpty))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.showsDivider {
                    Divider().padding(.leading, 58)
                }

                habitRow(row.habit)
            }
        }
        .padding(.vertical, 6)
        .groupedCard()
    }

    private func habitRow(_ habit: Habit) -> some View {
        HabitRowView(
            habit: habit,
            isCompleted: viewModel.isCompletedToday(habit),
            accessibilityLabel: viewModel.accessibilityLabel(for: habit),
            accessibilityHint: viewModel.accessibilityHint(for: habit),
            onToggle: { onToggle(habit) }
        )
        .padding(.horizontal, 16)
    }
}
