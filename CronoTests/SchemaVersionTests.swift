import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas del esquema versionado y su plan de migración.
///
/// Includes an on-disk V1 → V2 migration with every model and its relationships.
@MainActor
@Suite("Esquema y migración")
struct SchemaVersionTests {

    // MARK: - La versión

    @Test("La versión del esquema es 1.0.0")
    func versionIsOne() {
        #expect(CronoSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("El plan migra V1 a V2")
    func planIncludesV2() {
        let names = CronoMigrationPlan.schemas.map { String(describing: $0) }
        #expect(names == ["CronoSchemaV1", "CronoSchemaV2"])

        #expect(CronoMigrationPlan.stages.count == 1)
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
        let declared = CronoSchemaV2.models.map { String(describing: $0) }.sorted()
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

        #expect(container.schema.version == Schema.Version(2, 0, 0))
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

        // El día sale del propio hábito, no de una fecha escrita a mano: marcar
        // antes de haberlo creado está prohibido, así que una fecha fija deja
        // de valer en cuanto el reloj del CI la pasa.
        let day = habit.createdDayKey
        store.toggleCompletion(for: habit, on: day, today: day)

        let reminders = ReminderStore(context: context)
        let list = try #require(reminders.ensureDefaultList())
        reminders.createReminder(title: "Comprar pan", in: list, dueDayKey: day)

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

    @Test("Migrar conserva hábitos, registros, tareas, subtareas y alarmas")
    func migrationPreservesExistingData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        let habitID = UUID()
        let alarmID = UUID()

        try writeV1Store(at: url, habitID: habitID, alarmID: alarmID)
        try verifyV2Store(at: url, habitID: habitID, alarmID: alarmID)

        // Reopening after assigning a routine exercises disk persistence too.
        let schema = Schema.crono
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let reopened = try ModelContainer(for: schema, migrationPlan: CronoMigrationPlan.self, configurations: config)
        let habits = try reopened.mainContext.fetch(FetchDescriptor<Habit>())
        #expect(habits.first?.routine == .morning)
    }

    private func writeV1Store(at url: URL, habitID: UUID, alarmID: UUID) throws {
        let schema = Schema(versionedSchema: CronoSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = container.mainContext
        let habit = CronoSchemaV1.Habit(uuid: habitID, name: "Leer", notes: "20 páginas", color: .indigo, sortIndex: 3)
        let completion = CronoSchemaV1.HabitCompletion(dayKey: 20260914)
        context.insert(habit)
        context.insert(completion)
        completion.habit = habit

        let list = CronoSchemaV1.ReminderList(name: "Casa", color: .green)
        let task = CronoSchemaV1.Reminder(title: "Compra", dueDayKey: 20260915, priority: .high, recurrence: .daily)
        let step = CronoSchemaV1.Reminder(title: "Pan")
        context.insert(list)
        context.insert(task)
        context.insert(step)
        task.list = list
        step.parent = task
        let alarm = CronoSchemaV1.AlarmItem(minuteOfDay: 420, systemAlarmID: alarmID)
        context.insert(alarm)
        try context.save()
    }

    private func verifyV2Store(at url: URL, habitID: UUID, alarmID: UUID) throws {
        let schema = Schema.crono
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: CronoMigrationPlan.self, configurations: config)
        let context = container.mainContext
        let habit = try #require(context.fetch(FetchDescriptor<Habit>()).first)
        #expect(habit.uuid == habitID)
        #expect(habit.name == "Leer")
        #expect(habit.notes == "20 páginas")
        #expect(habit.color == .indigo)
        #expect(habit.sortIndex == 3)
        #expect(habit.routine == .anytime)
        #expect(habit.completions.count == 1)
        #expect(habit.isCompleted(on: 20260914))
        #expect(habit.completions.first?.habit?.uuid == habitID)
        let list = try #require(context.fetch(FetchDescriptor<ReminderList>()).first)
        let task = try #require(list.reminders.first)
        #expect(task.title == "Compra")
        #expect(task.priority == .high)
        #expect(task.recurrence == .daily)
        #expect(task.dueDayKey == 20260915)
        #expect(task.subtasks.first?.title == "Pan")
        #expect(task.subtasks.first?.parent?.uuid == task.uuid)
        let alarm = try #require(context.fetch(FetchDescriptor<AlarmItem>()).first)
        #expect(alarm.minuteOfDay == 420)
        #expect(alarm.systemAlarmID == alarmID)
        habit.routine = .morning
        try context.save()
    }
}
