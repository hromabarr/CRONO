import SwiftUI

/// Las tres secciones de la app.
enum AppTab: Hashable {
    case today
    case history
    case habits
}

/// Contenedor de pestañas y presentación de errores del almacén.
struct RootView: View {
    @Environment(HabitStore.self) private var store
    @State private var selectedTab: AppTab = .initial

    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    /// Necesario porque las propiedades almacenadas son privadas: el
    /// inicializador sintetizado sería privado y las exigiría todas.
    init() {}

    var body: some View {
        TabView(selection: $selectedTab) {
            // Los nombres dicen qué hay dentro. "Inicio" no le diría al usuario
            // en qué pestaña está el calendario.
            Tab("Hoy", systemImage: "checkmark.circle", value: AppTab.today) {
                TodayView(onCreateHabit: { selectedTab = .habits })
            }

            Tab("Historial", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }

            Tab("Hábitos", systemImage: "list.bullet", value: AppTab.habits) {
                HabitListView()
            }
        }
        .alert(
            "Algo ha fallado",
            isPresented: Binding(
                get: { store.failure != nil },
                set: { if !$0 { store.failure = nil } }
            ),
            presenting: store.failure
        ) { _ in
            Button("Entendido", role: .cancel) { store.failure = nil }
        } message: { failure in
            // Un fallo al guardar se cuenta. Tragárselo con `try?` haría que la
            // app pareciera haber guardado algo que no guardó.
            Text(failure.message)
        }
        // `nil` en modo automático: no fuerza nada y la app hereda el ajuste de
        // iOS, incluido el cambio al anochecer.
        .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview {
    let container = PreviewData.container()

    RootView()
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}
