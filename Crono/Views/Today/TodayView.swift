import SwiftData
import SwiftUI

/// Pantalla principal: qué toca hoy y cuánto llevas.
struct TodayView: View {
    /// Lleva al usuario a la pestaña de gestión desde el estado vacío.
    /// Un botón "Crear hábito" que no navegara a ninguna parte sería peor que
    /// no ponerlo.
    var onCreateHabit: () -> Void

    /// Los hábitos vienen de `@Query`, la fuente reactiva de SwiftData: al
    /// marcar uno, esta vista se redibuja sola. El ViewModel deriva y actúa,
    /// pero no consulta.
    @Query(
        filter: #Predicate<Habit> { $0.archivedAt == nil },
        sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]
    )
    private var activeHabits: [Habit]

    @Environment(HabitStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: TodayViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    // Ventana de un solo fotograma antes de que `task` construya
                    // el ViewModel con el store del entorno.
                    Color(.systemGroupedBackground)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hoy")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            if viewModel == nil { viewModel = TodayViewModel(store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Si la app se quedó abierta y cruzó la medianoche, "hoy" apunta a
            // ayer y la lista mostraría las marcas equivocadas.
            if phase == .active { viewModel?.refreshToday() }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: TodayViewModel) -> some View {
        let scheduled = viewModel.habitsScheduledToday(from: activeHabits)
        let progress = viewModel.progress(for: scheduled)

        if activeHabits.isEmpty {
            EmptyStateView.noHabits(onCreate: onCreateHabit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scheduled.isEmpty {
            EmptyStateView.nothingToday
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Text(viewModel.todayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)

                    TodayHeaderView(
                        progress: progress,
                        headline: viewModel.headline(for: progress),
                        detail: viewModel.detail(for: progress)
                    )

                    sectionLabel("Hábitos de hoy")

                    VStack(spacing: 0) {
                        ForEach(Array(scheduled.enumerated()), id: \.element.id) { index, habit in
                            HabitRowView(
                                habit: habit,
                                isCompleted: viewModel.isCompletedToday(habit),
                                accessibilityLabel: viewModel.accessibilityLabel(for: habit),
                                accessibilityHint: viewModel.accessibilityHint(for: habit),
                                onToggle: { viewModel.toggle(habit) }
                            )
                            .padding(.horizontal, 16)

                            if index < scheduled.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .groupedCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .padding(.horizontal, 4)
    }
}

#Preview("Con hábitos") {
    let container = PreviewData.container()

    TodayView(onCreateHabit: {})
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}

#Preview("Sin hábitos") {
    let container = PreviewData.emptyContainer()

    TodayView(onCreateHabit: {})
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}
