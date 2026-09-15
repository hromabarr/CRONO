import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas del esquema versionado y su plan de migración.
///
/// Ninguna de estas comprueba una migración —no hay ninguna todavía—. Lo que
/// vigilan es lo que sí puede romperse en silencio: que el esquema deje de
/// nombrar todos los modelos, o que el contenedor deje de abrirse con el plan
/// puesto.
@MainActor
@Suite("Esquema y migración")
struct SchemaVersionTests {

    // MARK: - La versión

    @Test("La versión del esquema es 1.0.0")
    func versionIsOne() {
        #expect(CronoSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("El plan declara la V1 y ninguna etapa")
    func planHasOnlyV1() {
        let names = CronoMigrationPlan.schemas.map { String(describing: $0) }
        #expect(names == ["CronoSchemaV1"])

        // Sin segunda versión no hay nada que migrar. El día que la haya, esta
        // prueba falla y obliga a mirar la nota de CronoSchema.swift sobre
        // congelar la V1 antes de tocar los tipos vivos.
        #expect(CronoMigrationPlan.stages.isEmpty)
    }

    // MARK: - Los modelos

    @Test("El esquema nombra los cinco modelos de la app")
    func schemaListsEveryModel() {
        // El fallo que esto atrapa es añadir un `@Model` nuevo y olvidarlo aquí:
        // compila igual, y luego falla al guardar con un error que no señala la
        // causa.
        let entities = Schema.crono.entities.map(\.name).sorted()
        let expected = ["AlarmItem", "Habit", "HabitCompletion", "Reminder", "ReminderList"]
        #expect(entities == expected)
    }

    @Test("La lista de modelos y las entidades del esquema no se separan")
    func modelsMatchEntities() {
        let declared = CronoSchemaV1.models.map { String(describing: $0) }.sorted()
        let entities = Schema.crono.entities.map(\.name).sorted()
        #expect(declared == entities)
    }

    // MARK: - El contenedor

    @Test("El contenedor abre con el plan de migración puesto")
    func containerOpensWithPlan() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.crono,
            migrationPlan: CronoMigrationPlan.self,
            configurations: configuration
        )

        #expect(container.schema.version == Schema.Version(1, 0, 0))
    }

    @Test("Los datos van y vuelven a través del esquema versionado")
    func dataRoundTrips() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.crono,
            migrationPlan: CronoMigrationPlan.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        // Uno de cada, para que la prueba falle si cualquiera de los cinco
        // modelos deja de estar registrado.
        let store = HabitStore(context: context)
        let habit = try #require(store.createHabit(name: "Estirar", schedule: .everyDay))
        store.toggleCompletion(for: habit, on: 20_260_914, today: 20_260_914)

        let reminders = ReminderStore(context: context)
        let list = try #require(reminders.ensureDefaultList())
        reminders.createReminder(title: "Comprar pan", in: list, dueDayKey: 20_260_914)

        let alarms = AlarmStore(context: context, scheduler: NoopAlarmScheduler())
        _ = await alarms.create(minuteOfDay: 7 * 60, label: "Despertar", schedule: .weekdays)

        let habits = try context.fetch(FetchDescriptor<Habit>())
        let completions = try context.fetch(FetchDescriptor<HabitCompletion>())
        let lists = try context.fetch(FetchDescriptor<ReminderList>())
        let tasks = try context.fetch(FetchDescriptor<Reminder>())
        let alarmItems = try context.fetch(FetchDescriptor<AlarmItem>())

        #expect(habits.count == 1)
        #expect(completions.count == 1)
        #expect(lists.count == 1)
        #expect(tasks.count == 1)
        #expect(alarmItems.count == 1)
    }
}
