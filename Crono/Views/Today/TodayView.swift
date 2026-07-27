import SwiftData
import SwiftUI

/// Pantalla principal: qué toca hoy y cuánto llevas.
///
/// La estructura es deliberadamente idéntica a la de `HistoryView`: un `@State`
/// con el ViewModel ya construido, sin opcionales y sin `if let` dentro del
/// `ViewBuilder`. La versión anterior guardaba un `TodayViewModel?` porque el
/// ViewModel necesitaba el `HabitStore` del entorno, y ese desenvuelto en pleno
/// `ViewBuilder` era lo que hacía que el inferidor de tipos de Swift se rindiera
/// al compilar este archivo.
struct TodayView: View {
    /// Lleva al usuario a la pestaña de gestión desde el estado vacío.
    /// Un botón "Crear hábito" que no navegara a ninguna parte sería peor que
    /// no ponerlo.
    private let onCreateHabit: () -> Void

    /// Los hábitos vienen de `@Query`, la fuente reactiva de SwiftData: al
    /// marcar uno, esta vista se redibuja sola.
    @Query(
        filter: #Predicate<Habit> { $0.archivedAt == nil },
        sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]
    )
    private var activeHabits: [Habit]

    @Environment(HabitStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = TodayViewModel()

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
            screen
        }
        .onChange(of: scenePhase) { _, phase in
            // Si la app se quedó abierta y cruzó la medianoche, "hoy" apunta a
            // ayer y la lista mostraría las marcas equivocadas.
            if phase == .active {
                viewModel.refreshToday()
            }
        }
    }

    private var screen: some View {
        TodayContent(
            viewModel: viewModel,
            habits: activeHabits,
            onToggle: toggle,
            onCreateHabit: onCreateHabit
        )
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Text("Hoy"))
        .navigationBarTitleDisplayMode(.large)
    }

    /// La escritura la pide la vista al store, que sigue siendo el único punto
    /// de mutación de los datos. El ViewModel solo deriva.
    private func toggle(_ habit: Habit) {
        store.toggleCompletion(for: habit, on: viewModel.today, today: viewModel.today)
    }
}

// MARK: - Contenido

private struct TodayContent: View {
    let viewModel: TodayViewModel
    let habits: [Habit]
    let onToggle: (Habit) -> Void
    let onCreateHabit: () -> Void

    /// Fuera del `body`: una declaración local dentro de un `ViewBuilder` es una
    /// de las cosas que más encarecen la inferencia de tipos.
    private var scheduled: [Habit] {
        viewModel.habitsScheduledToday(from: habits)
    }

    @ViewBuilder
    var body: some View {
        if habits.isEmpty {
            filling { EmptyStateView.noHabits(onCreate: onCreateHabit) }
        } else if scheduled.isEmpty {
            filling { EmptyStateView.nothingToday }
        } else {
            ScrollView {
                TodayScrollContent(
                    viewModel: viewModel,
                    scheduled: scheduled,
                    onToggle: onToggle
                )
            }
        }
    }

    private func filling<Content: View>(_ content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TodayScrollContent: View {
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
            TodayHabitsCard(
                viewModel: viewModel,
                habits: scheduled,
                onToggle: onToggle
            )
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

    private var summary: some View {
        let current = progress
        return TodayHeaderView(
            progress: current,
            headline: viewModel.headline(for: current),
            detail: viewModel.detail(for: current)
        )
    }
}

private struct TodayHabitsCard: View {
    let viewModel: TodayViewModel
    let habits: [Habit]
    let onToggle: (Habit) -> Void

    /// Fila ya resuelta: se sabe de antemano si lleva separador delante.
    ///
    /// Calcularlo aquí evita comparar `habit.uuid` con un `UUID?` dentro del
    /// `ForEach`; esa comparación obliga al inferidor a promover a opcional y a
    /// recorrer las sobrecargas genéricas de `!=` en pleno `ViewBuilder`.
    private struct Row: Identifiable {
        let habit: Habit
        let showsDivider: Bool

        var id: UUID { habit.uuid }
    }

    private var rows: [Row] {
        habits.enumerated().map { index, habit in
            Row(habit: habit, showsDivider: index > 0)
        }
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
