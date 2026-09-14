import SwiftData
import SwiftUI

/// Pantalla principal: todo lo que toca hoy, de las tres partes de la app.
///
/// Es lo que hace que Crono sea una app y no tres funciones compartiendo barra
/// de pestañas. Reúne hábitos, tareas vencidas o de hoy, y la próxima alarma —
/// las tres cosas que uno quiere saber al abrir el móvil por la mañana.
struct TodayView: View {
    /// Lleva al usuario a otra pestaña desde los estados vacíos y los enlaces
    /// «ver todas».
    private let onOpenTab: (AppTab) -> Void

    @Query(HabitQueries.active) private var activeHabits: [Habit]
    @Query(ReminderQueries.pending) private var pendingReminders: [Reminder]
    @Query(AlarmQueries.all) private var alarms: [AlarmItem]

    @Environment(HabitStore.self) private var store
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = TodayViewModel()
    @State private var showingSettings = false

    /// Obligatorio: con propiedades almacenadas privadas, el inicializador que
    /// sintetiza Swift también es privado y las exige todas.
    init(onOpenTab: @escaping (AppTab) -> Void) {
        self.onOpenTab = onOpenTab
    }

    var body: some View {
        NavigationStack {
            screen
        }
        .onChange(of: scenePhase) { _, phase in
            // Si la app se quedó abierta y cruzó la medianoche, «hoy» apunta a
            // ayer y la pantalla entera mostraría el día equivocado.
            if phase == .active {
                viewModel.refreshToday()
            }
        }
    }

    private var screen: some View {
        TodayContent(
            viewModel: viewModel,
            digest: digest,
            onToggleHabit: toggleHabit,
            onToggleReminder: toggleReminder,
            onOpenTab: onOpenTab
        )
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Text("Hoy"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Ajustes")
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    // MARK: - Datos

    /// Se resuelve una sola vez y baja hecho a las subvistas.
    private var digest: TodayDigest {
        let today = viewModel.today
        return TodayDigest(
            scheduledHabits: viewModel.habitsScheduledToday(from: activeHabits),
            reminders: pendingReminders.topLevel.dueThrough(today).byDueDateUndatedLast,
            nextAlarm: AlarmItem.next(from: alarms),
            today: today,
            nowMinuteOfDay: SmartReminderListView.currentMinuteOfDay()
        )
    }

    // MARK: - Acciones

    /// Las escrituras las piden las vistas a los almacenes, que siguen siendo el
    /// único punto de mutación. Los ViewModels solo derivan.
    private func toggleHabit(_ habit: Habit) {
        store.toggleCompletion(for: habit, on: viewModel.today, today: viewModel.today)
    }

    private func toggleReminder(_ reminder: Reminder) {
        reminderStore.toggleCompletion(for: reminder)
    }
}

#Preview("Con contenido") {
    let container = PreviewData.container()

    TodayView(onOpenTab: { _ in })
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
        .environment(PreviewData.reminderStore(for: container))
        .environment(PreviewData.alarmStore(for: container))
}

#Preview("Día vacío") {
    let container = PreviewData.emptyContainer()

    TodayView(onOpenTab: { _ in })
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
        .environment(PreviewData.reminderStore(for: container))
        .environment(PreviewData.alarmStore(for: container))
}
