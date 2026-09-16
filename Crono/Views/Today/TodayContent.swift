import SwiftUI

/// Elige entre el día vacío y el contenido de la pantalla Hoy.
struct TodayContent: View {
    let viewModel: TodayViewModel
    let digest: TodayDigest
    let onToggleHabit: (Habit) -> Void
    let onToggleReminder: (Reminder) -> Void
    let onOpenTab: (AppTab) -> Void
    let onAddHabit: () -> Void
    let onOpenRoutine: (HabitRoutine) -> Void

    var body: some View {
        if digest.showsEmptyState {
            emptyState
        } else {
            ScrollView {
                TodayScrollContent(
                    viewModel: viewModel,
                    digest: digest,
                    onToggleHabit: onToggleHabit,
                    onToggleReminder: onToggleReminder,
                    onOpenTab: onOpenTab,
                    onAddHabit: onAddHabit,
                    onOpenRoutine: onOpenRoutine
                )
            }
        }
    }

    /// Un único estado vacío para toda la pantalla.
    ///
    /// Antes había dos —«sin hábitos» y «hoy no toca nada»— porque la pantalla
    /// solo hablaba de hábitos. Ahora que reúne tres cosas, distinguir cuál de
    /// ellas falta sería contarle al usuario la arquitectura interna: lo que
    /// importa es que no tiene nada pendiente.
    private var emptyState: some View {
        EmptyStateView(
            title: "Nada pendiente",
            message: "No tienes hábitos ni tareas para hoy. Añade un hábito para empezar tu rutina.",
            systemImage: "checkmark.circle",
            actionTitle: "Añadir hábito",
            action: onAddHabit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
