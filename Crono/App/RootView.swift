import SwiftUI

/// Las secciones de la app.
///
/// Historial no está: es una pantalla que se abre desde Hábitos, no una sección
/// al mismo nivel. El historial *es* de los hábitos, y sacarlo de la barra deja
/// el sitio que necesitan las tareas y las alarmas — sin llegar a
/// cinco pestañas, que es más de lo que una barra sostiene con comodidad.
enum AppTab: Hashable {
    case today
    case reminders
    case habits
    case alarms
}

/// Contenedor de pestañas, apariencia y presentación de errores.
struct RootView: View {
    @Environment(HabitStore.self) private var store
    @Environment(ReminderStore.self) private var reminderStore
    @Environment(AlarmStore.self) private var alarmStore

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

            Tab("Tareas", systemImage: "list.bullet.rectangle", value: AppTab.reminders) {
                ReminderListsView()
            }

            Tab("Hábitos", systemImage: "repeat", value: AppTab.habits) {
                HabitListView()
            }

            Tab("Alarmas", systemImage: "alarm", value: AppTab.alarms) {
                AlarmListView()
            }
        }
        .alert(
            "Algo ha fallado",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { clearFailure() } }
            ),
            presenting: failure
        ) { _ in
            Button("Entendido", role: .cancel) { clearFailure() }
        } message: { failure in
            // Un fallo al guardar se cuenta. Tragárselo con `try?` haría que la
            // app pareciera haber guardado algo que no guardó.
            Text(failure.message)
        }
        // `nil` en modo automático: no fuerza nada y la app hereda el ajuste de
        // iOS, incluido el cambio al anochecer.
        .preferredColorScheme(appearance.colorScheme)
    }

    /// Los tres almacenes comparten una sola alerta.
    ///
    /// Dos `.alert` en la misma vista compiten por presentarse y uno se pierde;
    /// además, al usuario le da igual cuál de los tres subsistemas falló.
    private var failure: StoreFailure? {
        store.failure ?? reminderStore.failure ?? alarmStore.failure
    }

    private func clearFailure() {
        store.failure = nil
        reminderStore.failure = nil
        alarmStore.failure = nil
    }
}

#Preview {
    let container = PreviewData.container()

    RootView()
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
        .environment(PreviewData.reminderStore(for: container))
        .environment(PreviewData.alarmStore(for: container))
}
