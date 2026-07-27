import SwiftUI

/// Elige entre los dos estados vacíos de la pantalla Hoy y el contenido normal.
///
/// Cada rama es una propiedad con nombre y tipo propio. Antes las ramas se
/// construían con un ayudante genérico —`filling<Content: View>(_:) -> some
/// View`— llamado con un cierre desde dentro del `ViewBuilder`: el compilador
/// tenía que inferir `Content` desde el cierre y luego resolver el tipo opaco,
/// todo ello dentro de una cadena de `_ConditionalContent`. Eso es justo lo que
/// hacía que se rindiera con «unable to type-check this expression in reasonable
/// time».
struct TodayContent: View {
    let viewModel: TodayViewModel
    let habits: [Habit]
    let onToggle: (Habit) -> Void
    let onCreateHabit: () -> Void

    /// Fuera del `body`: una declaración local dentro de un `ViewBuilder` es una
    /// de las cosas que más encarecen la inferencia de tipos.
    private var scheduled: [Habit] {
        viewModel.habitsScheduledToday(from: habits)
    }

    var body: some View {
        if habits.isEmpty {
            noHabitsState
        } else if scheduled.isEmpty {
            nothingTodayState
        } else {
            scrollContent
        }
    }

    private var noHabitsState: some View {
        EmptyStateView.noHabits(onCreate: onCreateHabit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nothingTodayState: some View {
        EmptyStateView.nothingToday
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        ScrollView {
            TodayScrollContent(
                viewModel: viewModel,
                scheduled: scheduled,
                onToggle: onToggle
            )
        }
    }
}
