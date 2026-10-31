import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas de la copia de seguridad: lo que sale tiene que volver igual.
@MainActor
@Suite("Copia de seguridad")
struct BackupTests {

    struct Stores {
        let context: ModelContext
        let habits: HabitStore
        let reminders: ReminderStore
        let alarms: AlarmStore
        let scheduler: NoopAlarmScheduler
    }

    func makeStores() throws -> Stores {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema.crono, configurations: configuration)
        let context = ModelContext(container)
        let scheduler = NoopAlarmScheduler()
        return Stores(
            context: context,
            habits: HabitStore(context: context),
            reminders: ReminderStore(context: context, notifier: NoopReminderNotifier()),
            alarms: AlarmStore(context: context, scheduler: scheduler),
            scheduler: scheduler
        )
    }

    /// Un poco de todo: un hábito con cantidad y uno archivado, una lista con
    /// una tarea y su subtarea, y una alarma con desarme.
    func fill(_ stores: Stores) async throws {
        let water = try #require(stores.habits.createHabit(name: "Agua", routine: .morning, targetCount: 8, unit: "vasos"))
        let day = water.createdDayKey
        stores.habits.increment(water, on: day, today: day)
        stores.habits.increment(water, on: day, today: day)

        let read = try #require(stores.habits.createHabit(name: "Leer", color: .green, schedule: .weekdays))
        stores.habits.toggleCompletion(for: read, on: day, today: day)
        stores.habits.archive(read)

        let list = try #require(stores.reminders.createList(name: "Casa", color: .orange, symbolName: "house"))
        let task = try #require(
            stores.reminders.createReminder(
                title: "Compra",
                in: list,
                dueDayKey: day,
                dueMinuteOfDay: 18 * 60,
                priority: .high,
                recurrence: .daily
            )
        )
        _ = stores.reminders.createReminder(title: "Pan", in: list, parent: task)

        _ = await stores.alarms.create(
            minuteOfDay: 7 * 60,
            label: "Despertar",
            schedule: .weekdays,
            disarmMethod: .scannedCode(value: "CRONO"),
            disarmHint: "el baño",
            insistence: .untilDisarmed
        )
    }

    @Test("Exportar y restaurar en otra base devuelve los mismos datos")
    func roundTrip() async throws {
        let source = try makeStores()
        try await fill(source)
        let exported = try BackupService.snapshot(of: source.context)
        let data = try BackupService.encode(exported)

        let target = try makeStores()
        let decoded = try BackupService.decode(data)
        try await BackupService.restore(
            decoded,
            into: target.context,
            alarmStore: target.alarms,
            reminderStore: target.reminders
        )

        // Exportar lo restaurado da lo mismo que se leyó del archivo. Se compara
        // con lo leído y no con lo exportado porque el JSON guarda las fechas
        // al segundo; la fecha de exportación es lo único que cambia.
        var again = try BackupService.snapshot(of: target.context)
        again.exportedAt = decoded.exportedAt
        #expect(again == decoded)
        #expect(decoded.habits.count == exported.habits.count)
        #expect(decoded.reminders.count == exported.reminders.count)

        let habits = try target.context.fetch(FetchDescriptor<Habit>())
        let water = try #require(habits.first { $0.name == "Agua" })
        #expect(water.targetCount == 8)
        #expect(water.unit == "vasos")
        #expect(water.count(on: water.createdDayKey) == 2)
        #expect(water.routine == .morning)
        #expect(habits.contains { $0.name == "Leer" && !$0.isActive })

        let task = try #require(try target.context.fetch(FetchDescriptor<Reminder>()).first { $0.title == "Compra" })
        #expect(task.list?.name == "Casa")
        #expect(task.subtasks.first?.title == "Pan")
        #expect(task.recurrence == .daily)
        #expect(task.priority == .high)
    }

    @Test("Restaurar registra de nuevo las alarmas")
    func restoreSchedulesAlarms() async throws {
        let source = try makeStores()
        try await fill(source)
        let backup = try BackupService.snapshot(of: source.context)

        let target = try makeStores()
        try await BackupService.restore(
            backup,
            into: target.context,
            alarmStore: target.alarms,
            reminderStore: target.reminders
        )

        let alarm = try #require(try target.context.fetch(FetchDescriptor<AlarmItem>()).first)
        #expect(alarm.systemAlarmID != nil)
        #expect(target.scheduler.scheduled.count == 1)
        #expect(alarm.disarmMethod == .scannedCode(value: "CRONO"))
        #expect(alarm.insistence == .untilDisarmed)
        // Las vueltas también: la copia no las traía, se registran aquí.
        #expect(!alarm.scheduledFollowUps.isEmpty)
    }

    @Test("Restaurar sustituye lo que había y da de baja sus alarmas")
    func restoreReplaces() async throws {
        let stores = try makeStores()
        try await fill(stores)
        let backup = try BackupService.snapshot(of: stores.context)

        _ = stores.habits.createHabit(name: "Sobra")
        _ = await stores.alarms.create(minuteOfDay: 9 * 60, label: "Sobra")
        #expect(stores.scheduler.scheduled.count == 2)

        try await BackupService.restore(
            backup,
            into: stores.context,
            alarmStore: stores.alarms,
            reminderStore: stores.reminders
        )

        let names = try stores.context.fetch(FetchDescriptor<Habit>()).map(\.name).sorted()
        #expect(names == ["Agua", "Leer"])
        #expect(try stores.context.fetch(FetchDescriptor<AlarmItem>()).count == 1)
        // Solo queda registrada la alarma de la copia, no la que sobraba.
        #expect(stores.scheduler.scheduled.count == 1)
    }

    @Test("Un archivo roto no se lee")
    func brokenFile() throws {
        #expect(throws: BackupError.self) {
            try BackupService.decode(Data("no es una copia".utf8))
        }
    }

    @Test("Una copia de una versión más nueva no se abre")
    func newerFormat() throws {
        var backup = CronoBackup(
            formatVersion: CronoBackup.currentFormat + 1,
            exportedAt: .now,
            habits: [],
            lists: [],
            reminders: [],
            alarms: []
        )
        let data = try BackupService.encode(backup)
        #expect(throws: BackupError.self) {
            try BackupService.decode(data)
        }

        backup.formatVersion = CronoBackup.currentFormat
        let current = try BackupService.encode(backup)
        #expect(try BackupService.decode(current).habits.isEmpty)
    }

    @Test("La copia automática escribe una al día y conserva las últimas")
    func autoBackupKeepsLatest() throws {
        let stores = try makeStores()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for day in 0..<10 {
            let date = start.addingTimeInterval(TimeInterval(day * 86_400))
            AutoBackup.runIfNeeded(context: stores.context, now: date, in: directory)
            // Dos veces el mismo día no escriben dos copias.
            AutoBackup.runIfNeeded(context: stores.context, now: date, in: directory)
        }

        let files = AutoBackup.backups(in: directory)
        #expect(files.count == AutoBackup.keep)
        let lastName = AutoBackup.fileName(for: start.addingTimeInterval(9 * 86_400))
        #expect(files.last?.lastPathComponent == lastName)
    }
}
