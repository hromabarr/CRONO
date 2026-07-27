import SwiftUI

/// Cuerpo desplazable de la pantalla Hoy: fecha, anillo y lista.
struct TodayScrollContent: View {
    let viewModel: TodayViewModel
    let scheduled: [Habit]
    let onToggle: (Habit) -> Void

    private var progress: TodayViewModel.DayProgress {
        viewModel.progress(for: scheduled)
    }

    var body: some View {
        VStack(spacing: 0) {
            dateHeader
            summary
            SectionLabel("Hábitos de hoy")
            habitsCard
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var dateHeader: some View {
        Text(viewModel.todayTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
    }

    private var summary: TodayHeaderView {
        // Tipo de retorno concreto en lugar de `some View`: no hay nada que
        // resolver, y esta propiedad se evalúa en cada redibujado.
        let current = progress
        return TodayHeaderView(
            progress: current,
            headline: viewModel.headline(for: current),
            detail: viewModel.detail(for: current)
        )
    }

    private var habitsCard: TodayHabitsCard {
        TodayHabitsCard(
            viewModel: viewModel,
            habits: scheduled,
            onToggle: onToggle
        )
    }
}
