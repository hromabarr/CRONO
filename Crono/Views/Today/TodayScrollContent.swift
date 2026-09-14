import SwiftUI

/// Cuerpo desplazable de la pantalla Hoy.
///
/// El orden no es casual: primero el anillo con los hábitos, porque el anillo
/// mide justo eso y separarlos de lo que cuentan lo haría ilegible; después las
/// tareas, que son lo variable del día; y al final la alarma, que cierra.
struct TodayScrollContent: View {
    let viewModel: TodayViewModel
    let digest: TodayDigest
    let onToggleHabit: (Habit) -> Void
    let onToggleReminder: (Reminder) -> Void
    let onOpenTab: (AppTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            dateHeader
            habitsBlock
            tasksBlock
            alarmBlock
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Bloques

    private var dateHeader: some View {
        Text(viewModel.todayTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var habitsBlock: some View {
        if !digest.scheduledHabits.isEmpty {
            summary
            SectionLabel("Hábitos de hoy")
            TodayHabitsCard(
                viewModel: viewModel,
                habits: digest.scheduledHabits,
                onToggle: onToggleHabit
            )
        }
    }

    /// El anillo solo mide hábitos, y su texto lo dice.
    ///
    /// Mezclar tareas en el porcentaje lo volvería ruido: un día con veinte
    /// tareas ahogaría los hábitos, y dejaría de casar con el Historial, que
    /// cuenta días perfectos de hábitos.
    private var summary: TodayHeaderView {
        let progress = viewModel.progress(for: digest.scheduledHabits)
        return TodayHeaderView(
            progress: progress,
            headline: viewModel.headline(for: progress),
            detail: viewModel.detail(for: progress)
        )
    }

    @ViewBuilder
    private var tasksBlock: some View {
        if !digest.reminders.isEmpty {
            SectionLabel("Tareas de hoy")

            TodayTasksCard(
                reminders: digest.visibleReminders,
                today: digest.today,
                nowMinuteOfDay: digest.nowMinuteOfDay,
                onToggle: onToggleReminder
            )

            if digest.hiddenReminderCount > 0 {
                Button {
                    onOpenTab(.reminders)
                } label: {
                    Text("Ver las \(digest.hiddenReminderCount) restantes")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 9)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var alarmBlock: some View {
        if let alarm = digest.nextAlarm {
            SectionLabel("Próxima alarma")
            TodayNextAlarmCard(alarm: alarm, isRegistered: alarm.systemAlarmID != nil)
        }
    }
}
