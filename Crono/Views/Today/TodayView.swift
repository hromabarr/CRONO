import SwiftData
import SwiftUI

/// Pantalla principal: qué toca hoy y cuánto llevas.
///
/// El contenido vive en archivos separados —`TodayContent`, `TodayScrollContent`,
/// `TodayHabitsCard`— y no como tipos privados aquí dentro. Aparte de leerse
/// mejor, si el compilador vuelve a atascarse señalará un archivo pequeño en
/// lugar de uno con cuatro vistas, que es la diferencia entre saber dónde está el
/// problema y tener que deducirlo.
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
    /// `activeHabits` como parámetro.
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
