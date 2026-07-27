import SwiftData
import SwiftUI

@main
struct CronoApp: App {
    private let container: ModelContainer
    @State private var store: HabitStore

    /// Aviso persistente si la base en disco no se pudo abrir.
    private let storageWarning: String?

    init() {
        let schema = Schema([Habit.self, HabitCompletion.self])
        var warning: String?
        let resolved: ModelContainer

        do {
            resolved = try ModelContainer(for: schema)
        } catch {
            // Si el almacén en disco falla —base corrupta, sin espacio— la app
            // arranca en memoria en lugar de cerrarse de golpe. Se pierde la
            // persistencia, pero el usuario puede usarla y, sobre todo, se le
            // dice lo que pasa en vez de dejarle creyendo que guardó sus datos.
            warning = """
                No se ha podido abrir la base de datos, así que esta sesión no \
                se guardará. Reinstalar la app suele resolverlo.
                """
            do {
                resolved = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                // Si ni siquiera un contenedor en memoria arranca, no hay app
                // posible: es mejor un fallo explicado que un estado imposible.
                fatalError("SwiftData no pudo inicializarse en ningún modo: \(error)")
            }
        }

        self.container = resolved
        self.storageWarning = warning
        _store = State(initialValue: HabitStore(context: resolved.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    #if DEBUG
                    // Solo hace algo si se lanzó con `-seedSampleData`, que es
                    // lo que hace la sesión de capturas automáticas en CI.
                    LaunchArguments.seedIfNeeded(container.mainContext)
                    #endif

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
