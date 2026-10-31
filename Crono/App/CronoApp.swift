import SwiftData
import SwiftUI

@main
struct CronoApp: App {
    private let container: ModelContainer
    @State private var store: HabitStore
    @State private var reminderStore: ReminderStore
    @State private var alarmStore: AlarmStore

    /// Aviso persistente si la base en disco no se pudo abrir.
    private let storageWarning: String?

    init() {
        let persistence = CronoPersistence.shared
        self.container = persistence.container
        self.storageWarning = persistence.storageWarning
        _store = State(initialValue: persistence.habitStore)
        _reminderStore = State(initialValue: persistence.reminderStore)
        _alarmStore = State(initialValue: persistence.alarmStore)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(reminderStore)
                .environment(alarmStore)
                .task {
                    #if DEBUG
                    // Solo hace algo si se lanzó con `-seedSampleData`, que es
                    // lo que hace la sesión de capturas automáticas en CI.
                    LaunchArguments.seedIfNeeded(container.mainContext)
                    #endif

                    // Sin al menos una lista, la pantalla de tareas sería un
                    // callejón sin salida: no habría dónde poner la primera.
                    reminderStore.ensureDefaultList()

                    // Las alarmas del sistema se pierden al reinstalar la app; una
                    // que el usuario ve activada tiene que volver a sonar.
                    await alarmStore.resyncAll()

                    // Una copia al día en Archivos, por si hay que reinstalar.
                    AutoBackup.runIfNeeded(context: container.mainContext)

                    if let storageWarning {
                        store.failure = StoreFailure(
                            action: "usar el almacenamiento",
                            reason: storageWarning
                        )
                    }
                }
        }
        .modelContainer(container)
    }
}
