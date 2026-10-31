import SwiftData
import SwiftUI

/// La base de datos y los almacenes de la app, uno solo para todos.
///
/// Sale de `CronoApp` porque ahora hay más de una puerta de entrada: los
/// Atajos y Siri también leen y escriben. Si cada uno abriera su propio
/// contenedor habría dos copias de la base en memoria que no se ven entre sí,
/// y lo que se marcase desde Siri no aparecería en Hoy hasta reiniciar.
@MainActor
final class CronoPersistence {
    static let shared = CronoPersistence()

    let container: ModelContainer
    let habitStore: HabitStore
    let reminderStore: ReminderStore
    let alarmStore: AlarmStore

    /// Aviso persistente si la base en disco no se pudo abrir.
    let storageWarning: String?

    private init() {
        // La lista de modelos actual vive en `CronoSchemaV4`, y el plan de migración
        // viaja con ella: sin él, el primer cambio de forma de los datos
        // invalidaría el almacén del usuario en lugar de migrarlo.
        let schema = Schema.crono
        var warning: String?
        let resolved: ModelContainer

        Self.ensureApplicationSupportExists()

        do {
            resolved = try ModelContainer(for: schema, migrationPlan: CronoMigrationPlan.self)
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
                    migrationPlan: CronoMigrationPlan.self,
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
        self.habitStore = HabitStore(context: resolved.mainContext)
        // Mismo patron que las alarmas: el notificador real solo si el
        // framework existe; si no, la app funciona igual y las tareas
        // simplemente no avisan.
        #if canImport(UserNotifications)
        let notifier: any ReminderNotifying = UserNotificationNotifier()
        #else
        let notifier: any ReminderNotifying = NoopReminderNotifier(authorization: .unavailable)
        #endif
        self.reminderStore = ReminderStore(context: resolved.mainContext, notifier: notifier)

        // El planificador real solo existe si AlarmKit está disponible; si no, la
        // app guarda y lista alarmas igual, y la interfaz avisa de que no van a
        // sonar. Es mejor que no poder crearlas.
        #if canImport(AlarmKit)
        let scheduler: any AlarmScheduling = AlarmKitScheduler()
        #else
        let scheduler: any AlarmScheduling = NoopAlarmScheduler(authorization: .unavailable)
        #endif
        self.alarmStore = AlarmStore(context: resolved.mainContext, scheduler: scheduler)
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
    /// `init` ya cae a un contenedor en memoria y avisa al usuario.
    private static func ensureApplicationSupportExists() {
        _ = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}
