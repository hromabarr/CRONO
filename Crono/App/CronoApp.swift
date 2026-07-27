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

        Self.ensureApplicationSupportExists()

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

    /// Crea `Application Support` si no existe.
    ///
    /// SwiftData guarda ahí su `default.store`, pero **no crea el directorio**:
    /// en un contenedor recién instalado —lo habitual en un simulador de CI— la
    /// carpeta puede no existir y la apertura del almacén falla con
    /// `errno 2 / No such file or directory`.
    ///
    /// `url(for:in:appropriateFor:create:)` con `create: true` la crea si falta y
    /// no hace nada si ya está. Si aun así falla, no se hace nada aquí: el
    /// `init` de abajo ya cae a un contenedor en memoria y avisa al usuario.
    private static func ensureApplicationSupportExists() {
        _ = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
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
