import SwiftData
import SwiftUI

/// Pantalla principal: qué toca hoy y cuánto llevas.
///
/// El cuerpo está troceado en subvistas pequeñas a propósito. Con todo el
/// contenido en un solo `body`, el inferidor de tipos de Swift se rinde con un
/// «unable to type-check this expression in reasonable time»: cada modificador
/// anidado multiplica las combinaciones que tiene que resolver.
struct TodayView: View {
    /// Lleva al usuario a la pestaña de gestión desde el estado vacío.
    /// Un botón "Crear hábito" que no navegara a ninguna parte sería peor que
    /// no ponerlo.
    private let onCreateHabit: () -> Void

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

    /// Inicializador explícito.
    ///
    /// Es obligatorio: al haber propiedades almacenadas `private` —el `@Query`
    /// entre ellas—, el que sintetiza Swift también es privado y además exige
    /// `activeHabits` como parámetro, así que `TodayView(...)` no compila desde
    /// fuera del propio tipo.
    init(onCreateHabit: @escaping () -> Void) {
        self.onCreateHabit = onCreateHabit
    }

    var body: some View {
        NavigationStack {
            container
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
    private var container: some View {
        if let viewModel {
            TodayContent(
                viewModel: viewModel,
                habits: activeHabits,
                onCreateHabit: onCreateHabit
            )
        } else {
            // Ventana de un solo fotograma antes de que `task` construya el
            // ViewModel con el store del entorno.
            Color(.systemGroupedBackground)
        }
    }
}

// MARK: - Contenido

private struct TodayContent: View {
    let viewModel: TodayViewModel
    let habits: [Habit]
    let onCreateHabit: () -> Void

    var body: some View {
        let scheduled = viewModel.habitsScheduledToday(from: habits)

        if habits.isEmpty {
            EmptyStateView.noHabits(onCreate: onCreateHabit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scheduled.isEmpty {
            EmptyStateView.nothingToday
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                TodayScrollContent(viewModel: viewModel, scheduled: scheduled)
            }
        }
    }
}

private struct TodayScrollContent: View {
    let viewModel: TodayViewModel
    let scheduled: [Habit]

    var body: some View {
        let progress = viewModel.progress(for: scheduled)

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

            SectionLabel("Hábitos de hoy")

            TodayHabitsCard(viewModel: viewModel, habits: scheduled)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
}

private struct TodayHabitsCard: View {
    let viewModel: TodayViewModel
    let habits: [Habit]

    private var firstID: UUID? { habits.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(habits) { habit in
                // Separador delante de todas menos la primera: así no hace falta
                // el índice, y con él desaparece el `Array(...enumerated())` con
                // `id:` por key path que atascaba al inferidor de tipos.
                if habit.id != firstID {
                    Divider().padding(.leading, 58)
                }

                row(habit)
            }
        }
        .padding(.vertical, 6)
        .groupedCard()
    }

    private func row(_ habit: Habit) -> some View {
        HabitRowView(
            habit: habit,
            isCompleted: viewModel.isCompletedToday(habit),
            accessibilityLabel: viewModel.accessibilityLabel(for: habit),
            accessibilityHint: viewModel.accessibilityHint(for: habit),
            onToggle: { viewModel.toggle(habit) }
        )
        .padding(.horizontal, 16)
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
