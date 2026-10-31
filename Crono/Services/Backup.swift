import Foundation
import SwiftData

/// Todos los datos del usuario en un archivo.
///
/// Existe porque Crono se instala fuera de la App Store: si un día hay que
/// borrarla y reinstalarla, o el certificado con el que se firmó cambia, la
/// base de datos se va con la app. Este archivo es lo que sobrevive.
///
/// Son copias planas de las columnas de cada modelo, con las relaciones
/// escritas como identificadores. No se guardan los identificadores de las
/// alarmas en el sistema —`systemAlarmID` ni las vueltas—: solo valen en el
/// aparato donde se registraron, y al restaurar se registran de nuevo.
struct CronoBackup: Codable, Equatable {
    /// Sube cuando cambie la forma del archivo. Un archivo de una versión más
    /// nueva no se abre: mejor decirlo que restaurar a medias.
    static let currentFormat = 1

    var formatVersion: Int
    var exportedAt: Date
    var habits: [HabitRecord]
    var lists: [ListRecord]
    var reminders: [ReminderRecord]
    var alarms: [AlarmRecord]

    struct HabitRecord: Codable, Equatable {
        var uuid: UUID
        var name: String
        var notes: String
        var colorRaw: String
        var scheduledWeekdaysMask: Int
        var createdAt: Date
        var archivedAt: Date?
        var sortIndex: Int
        var routineRaw: String?
        var targetCount: Int
        var unit: String
        var completions: [CompletionRecord]
    }

    struct CompletionRecord: Codable, Equatable {
        var uuid: UUID
        var dayKey: DayKey
        var completedAt: Date
        var count: Int
    }

    struct ListRecord: Codable, Equatable {
        var uuid: UUID
        var name: String
        var colorRaw: String
        var symbolName: String
        var createdAt: Date
        var sortIndex: Int
    }

    struct ReminderRecord: Codable, Equatable {
        var uuid: UUID
        var title: String
        var notes: String
        var isCompleted: Bool
        var completedAt: Date?
        var createdAt: Date
        var sortIndex: Int
        var dueDayKey: DayKey?
        var dueMinuteOfDay: Int?
        var priorityRaw: Int
        var isFlagged: Bool
        var recurrenceRaw: String?
        /// La lista a la que pertenece. Las subtareas la heredan de su madre y
        /// pueden no tenerla.
        var listID: UUID?
        /// La tarea madre, si es una subtarea.
        var parentID: UUID?
    }

    struct AlarmRecord: Codable, Equatable {
        var uuid: UUID
        var label: String
        var minuteOfDay: Int
        var scheduledWeekdaysMask: Int
        var isEnabled: Bool
        var snoozeEnabled: Bool
        var createdAt: Date
        var sortIndex: Int
        var disarmMethodRaw: String?
        var disarmHint: String
        var insistenceIntervalMinutes: Int
        var insistenceRepeats: Int
        var soundRaw: String
        var followUpSoundRaw: String
    }

    /// «12 hábitos, 30 tareas y 2 alarmas», para confirmar antes de restaurar.
    var summary: String {
        "\(habits.count) hábitos, \(reminders.count) tareas y \(alarms.count) alarmas"
    }
}

enum BackupError: LocalizedError {
    case unreadable
    case newerFormat

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "El archivo no es una copia de Crono o está dañado."
        case .newerFormat:
            "La copia es de una versión de Crono más nueva. Actualiza la app y vuelve a intentarlo."
        }
    }
}

/// Exporta y restaura `CronoBackup`.
@MainActor
enum BackupService {

    // MARK: - Exportar

    static func snapshot(of context: ModelContext, at date: Date = .now) throws -> CronoBackup {
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortIndex)]))
        let lists = try context.fetch(FetchDescriptor<ReminderList>(sortBy: [SortDescriptor(\.sortIndex)]))
        let reminders = try context.fetch(FetchDescriptor<Reminder>(sortBy: [SortDescriptor(\.createdAt)]))
        let alarms = try context.fetch(AlarmQueries.all)

        var habitRecords: [CronoBackup.HabitRecord] = []
        for habit in habits {
            var completions: [CronoBackup.CompletionRecord] = []
            for completion in habit.completions {
                completions.append(
                    CronoBackup.CompletionRecord(
                        uuid: completion.uuid,
                        dayKey: completion.dayKey,
                        completedAt: completion.completedAt,
                        count: completion.count
                    )
                )
            }
            // Ordenados por día: dos exportaciones de los mismos datos dan el
            // mismo archivo, y así se pueden comparar.
            completions.sort { $0.dayKey < $1.dayKey }

            habitRecords.append(
                CronoBackup.HabitRecord(
                    uuid: habit.uuid,
                    name: habit.name,
                    notes: habit.notes,
                    colorRaw: habit.colorRaw,
                    scheduledWeekdaysMask: habit.scheduledWeekdaysMask,
                    createdAt: habit.createdAt,
                    archivedAt: habit.archivedAt,
                    sortIndex: habit.sortIndex,
                    routineRaw: habit.routineRaw,
                    targetCount: habit.targetCount,
                    unit: habit.unit,
                    completions: completions
                )
            )
        }

        var listRecords: [CronoBackup.ListRecord] = []
        for list in lists {
            listRecords.append(
                CronoBackup.ListRecord(
                    uuid: list.uuid,
                    name: list.name,
                    colorRaw: list.colorRaw,
                    symbolName: list.symbolName,
                    createdAt: list.createdAt,
                    sortIndex: list.sortIndex
                )
            )
        }

        var reminderRecords: [CronoBackup.ReminderRecord] = []
        for reminder in reminders {
            reminderRecords.append(
                CronoBackup.ReminderRecord(
                    uuid: reminder.uuid,
                    title: reminder.title,
                    notes: reminder.notes,
                    isCompleted: reminder.isCompleted,
                    completedAt: reminder.completedAt,
                    createdAt: reminder.createdAt,
                    sortIndex: reminder.sortIndex,
                    dueDayKey: reminder.dueDayKey,
                    dueMinuteOfDay: reminder.dueMinuteOfDay,
                    priorityRaw: reminder.priorityRaw,
                    isFlagged: reminder.isFlagged,
                    recurrenceRaw: reminder.recurrenceRaw,
                    listID: reminder.list?.uuid,
                    parentID: reminder.parent?.uuid
                )
            )
        }

        // Por identificador y no por fecha de creación: el JSON guarda las
        // fechas al segundo, y dos tareas creadas en el mismo segundo saldrían
        // en otro orden al exportar lo restaurado.
        reminderRecords.sort { $0.uuid.uuidString < $1.uuid.uuidString }

        var alarmRecords: [CronoBackup.AlarmRecord] = []
        for alarm in alarms {
            alarmRecords.append(
                CronoBackup.AlarmRecord(
                    uuid: alarm.uuid,
                    label: alarm.label,
                    minuteOfDay: alarm.minuteOfDay,
                    scheduledWeekdaysMask: alarm.scheduledWeekdaysMask,
                    isEnabled: alarm.isEnabled,
                    snoozeEnabled: alarm.snoozeEnabled,
                    createdAt: alarm.createdAt,
                    sortIndex: alarm.sortIndex,
                    disarmMethodRaw: alarm.disarmMethodRaw,
                    disarmHint: alarm.disarmHint,
                    insistenceIntervalMinutes: alarm.insistenceIntervalMinutes,
                    insistenceRepeats: alarm.insistenceRepeats,
                    soundRaw: alarm.soundRaw,
                    followUpSoundRaw: alarm.followUpSoundRaw
                )
            )
        }

        return CronoBackup(
            formatVersion: CronoBackup.currentFormat,
            exportedAt: date,
            habits: habitRecords,
            lists: listRecords,
            reminders: reminderRecords,
            alarms: alarmRecords
        )
    }

    nonisolated static func encode(_ backup: CronoBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    nonisolated static func decode(_ data: Data) throws -> CronoBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: CronoBackup
        do {
            backup = try decoder.decode(CronoBackup.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
        guard backup.formatVersion <= CronoBackup.currentFormat else {
            throw BackupError.newerFormat
        }
        return backup
    }

    // MARK: - Restaurar

    /// Sustituye todos los datos por los de la copia.
    ///
    /// Primero se dan de baja las alarmas y los avisos del sistema: después de
    /// borrar los modelos ya no habría de dónde leer sus identificadores, y
    /// quedarían sonando por datos que ya no existen. Si el guardado falla se
    /// deshace todo y se vuelven a registrar las alarmas de antes.
    static func restore(
        _ backup: CronoBackup,
        into context: ModelContext,
        alarmStore: AlarmStore,
        reminderStore: ReminderStore
    ) async throws {
        await alarmStore.unscheduleAll()
        await reminderStore.cancelAllNotifications()

        do {
            try deleteEverything(in: context)
            insert(backup, into: context)
            try context.save()
        } catch {
            context.rollback()
            await alarmStore.resyncAll()
            await reminderStore.resyncNotifications()
            throw error
        }

        await alarmStore.resyncAll()
        await reminderStore.resyncNotifications()
    }

    private static func deleteEverything(in context: ModelContext) throws {
        // Uno a uno y no con `delete(model:)`: el borrado por lotes no pasa por
        // las reglas de cascada de cada relación.
        for completion in try context.fetch(FetchDescriptor<HabitCompletion>()) {
            context.delete(completion)
        }
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            context.delete(habit)
        }
        for reminder in try context.fetch(FetchDescriptor<Reminder>()) {
            context.delete(reminder)
        }
        for list in try context.fetch(FetchDescriptor<ReminderList>()) {
            context.delete(list)
        }
        for alarm in try context.fetch(FetchDescriptor<AlarmItem>()) {
            context.delete(alarm)
        }
    }

    private static func insert(_ backup: CronoBackup, into context: ModelContext) {
        for record in backup.habits {
            let habit = Habit(
                uuid: record.uuid,
                name: record.name,
                notes: record.notes,
                schedule: WeekdaySet(rawValue: record.scheduledWeekdaysMask),
                createdAt: record.createdAt,
                archivedAt: record.archivedAt,
                sortIndex: record.sortIndex,
                targetCount: record.targetCount,
                unit: record.unit
            )
            // Las columnas en bruto, no los tipos: un color o una rutina que
            // esta versión no conozca se conserva tal cual en vez de perderse.
            habit.colorRaw = record.colorRaw
            habit.routineRaw = record.routineRaw
            context.insert(habit)

            for item in record.completions {
                let completion = HabitCompletion(
                    uuid: item.uuid,
                    dayKey: item.dayKey,
                    completedAt: item.completedAt,
                    count: item.count
                )
                context.insert(completion)
                completion.habit = habit
            }
        }

        var listsByID: [UUID: ReminderList] = [:]
        for record in backup.lists {
            let list = ReminderList(
                uuid: record.uuid,
                name: record.name,
                symbolName: record.symbolName,
                createdAt: record.createdAt,
                sortIndex: record.sortIndex
            )
            list.colorRaw = record.colorRaw
            context.insert(list)
            listsByID[record.uuid] = list
        }

        var remindersByID: [UUID: Reminder] = [:]
        for record in backup.reminders {
            let reminder = Reminder(
                uuid: record.uuid,
                title: record.title,
                notes: record.notes,
                isCompleted: record.isCompleted,
                completedAt: record.completedAt,
                createdAt: record.createdAt,
                sortIndex: record.sortIndex,
                dueDayKey: record.dueDayKey,
                dueMinuteOfDay: record.dueMinuteOfDay,
                isFlagged: record.isFlagged
            )
            reminder.priorityRaw = record.priorityRaw
            reminder.recurrenceRaw = record.recurrenceRaw
            context.insert(reminder)
            remindersByID[record.uuid] = reminder
        }

        // Las relaciones al final, cuando ya existen las dos puntas.
        for record in backup.reminders {
            guard let reminder = remindersByID[record.uuid] else { continue }
            if let listID = record.listID { reminder.list = listsByID[listID] }
            if let parentID = record.parentID { reminder.parent = remindersByID[parentID] }
        }

        for record in backup.alarms {
            let alarm = AlarmItem(
                uuid: record.uuid,
                label: record.label,
                minuteOfDay: record.minuteOfDay,
                schedule: WeekdaySet(rawValue: record.scheduledWeekdaysMask),
                isEnabled: record.isEnabled,
                snoozeEnabled: record.snoozeEnabled,
                createdAt: record.createdAt,
                sortIndex: record.sortIndex
            )
            alarm.disarmMethodRaw = record.disarmMethodRaw
            alarm.disarmHint = record.disarmHint
            alarm.insistenceIntervalMinutes = record.insistenceIntervalMinutes
            alarm.insistenceRepeats = record.insistenceRepeats
            alarm.soundRaw = record.soundRaw
            alarm.followUpSoundRaw = record.followUpSoundRaw
            context.insert(alarm)
        }
    }
}

// MARK: - Copia automática

/// Una copia al día en `Documentos/Copias`, visible desde la app Archivos.
///
/// Es la red para el día en que no te acordaste de exportar: si hay que
/// reinstalar, la última copia está en el iPhone, fuera de la app.
@MainActor
enum AutoBackup {
    /// Cuántas copias diarias se conservan.
    static let keep = 7

    static var directory: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Copias", isDirectory: true)
    }

    /// Escribe la copia de hoy si aún no existe y borra las que sobran.
    ///
    /// Los fallos se callan a propósito: una copia automática que no se pudo
    /// escribir no merece interrumpir al usuario al abrir la app, y la manual
    /// sigue disponible.
    static func runIfNeeded(context: ModelContext, now: Date = .now, in directory: URL? = AutoBackup.directory) {
        guard let directory else { return }
        let file = directory.appendingPathComponent(fileName(for: now))
        guard !FileManager.default.fileExists(atPath: file.path) else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try BackupService.encode(BackupService.snapshot(of: context, at: now))
            try data.write(to: file, options: .atomic)
            prune(directory)
        } catch {
            return
        }
    }

    /// `crono-2026-10-31.json`. La fecha en el nombre ordena los archivos por
    /// sí sola, y se lee en Archivos sin abrirlos.
    static func fileName(for date: Date, calendar: Calendar = AppCalendar.current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "crono-%04d-%02d-%02d.json", year, month, day)
    }

    /// Fecha de la copia automática más reciente, si hay alguna.
    static func latestBackupDate(in directory: URL? = AutoBackup.directory) -> Date? {
        guard let latest = backups(in: directory).last else { return nil }
        let values = try? latest.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    /// Las copias automáticas, de la más antigua a la más reciente.
    static func backups(in directory: URL?) -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey]
              )
        else { return [] }

        return files
            .filter { $0.lastPathComponent.hasPrefix("crono-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func prune(_ directory: URL) {
        let all = backups(in: directory)
        guard all.count > keep else { return }
        for url in all.prefix(all.count - keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
