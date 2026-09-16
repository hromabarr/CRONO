import Foundation
import SwiftData

/// Definiciones congeladas tal y como se publicaron en la V2.
///
/// La V2 es la V1 más `routineRaw` en `Habit`. No se toca nada de aquí al
/// evolucionar a la V3: en cuanto una de estas clases describa la forma nueva,
/// la migración concluye que no hay nada que migrar y se aplica en silencio.
///
/// Generada a partir de `CronoSchemaV1.swift` y comprobada propiedad a
/// propiedad contra los modelos vivos, no copiada a mano.
enum CronoSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Habit.self, HabitCompletion.self, ReminderList.self, Reminder.self, AlarmItem.self]
    }

    @Model
    final class Habit {
        @Attribute(.unique) var uuid: UUID

        var name: String

        var notes: String

        var colorRaw: String

        var scheduledWeekdaysMask: Int

        var createdAt: Date

        var archivedAt: Date?

        var sortIndex: Int

        var routineRaw: String?

        @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
        var completions: [HabitCompletion]

        init(
            uuid: UUID = UUID(),
            name: String,
            notes: String = "",
            color: HabitColor = .default,
            schedule: WeekdaySet = .everyDay,
            createdAt: Date = .now,
            archivedAt: Date? = nil,
            sortIndex: Int = 0,
            routine: HabitRoutine = .anytime
        ) {
            self.uuid = uuid
            self.name = name
            self.notes = notes
            self.colorRaw = color.rawValue
            self.scheduledWeekdaysMask = schedule.rawValue
            self.createdAt = createdAt
            self.archivedAt = archivedAt
            self.sortIndex = sortIndex
            self.routineRaw = routine.rawValue
            self.completions = []
        }
    }

    @Model
    final class HabitCompletion {
        #Index<HabitCompletion>([\.dayKey])

        @Attribute(.unique) var uuid: UUID

        var dayKey: DayKey

        var completedAt: Date

        var habit: Habit?

        init(
            uuid: UUID = UUID(),
            dayKey: DayKey,
            completedAt: Date = .now,
            habit: Habit? = nil
        ) {
            self.uuid = uuid
            self.dayKey = dayKey
            self.completedAt = completedAt
            self.habit = habit
        }
    }

    @Model
    final class ReminderList {
        @Attribute(.unique) var uuid: UUID

        var name: String

        var colorRaw: String

        var symbolName: String

        var createdAt: Date

        var sortIndex: Int

        @Relationship(deleteRule: .cascade, inverse: \Reminder.list)
        var reminders: [Reminder]

        init(
            uuid: UUID = UUID(),
            name: String,
            color: HabitColor = .default,
            symbolName: String = "list.bullet",
            createdAt: Date = .now,
            sortIndex: Int = 0
        ) {
            self.uuid = uuid
            self.name = name
            self.colorRaw = color.rawValue
            self.symbolName = symbolName
            self.createdAt = createdAt
            self.sortIndex = sortIndex
            self.reminders = []
        }
    }

    @Model
    final class Reminder {
        @Attribute(.unique) var uuid: UUID

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


        var list: ReminderList?

        @Relationship(deleteRule: .cascade, inverse: \Reminder.parent)
        var subtasks: [Reminder]

        var parent: Reminder?

        init(
            uuid: UUID = UUID(),
            title: String,
            notes: String = "",
            isCompleted: Bool = false,
            completedAt: Date? = nil,
            createdAt: Date = .now,
            sortIndex: Int = 0,
            dueDayKey: DayKey? = nil,
            dueMinuteOfDay: Int? = nil,
            priority: ReminderPriority = .none,
            isFlagged: Bool = false,
            recurrence: RecurrenceRule? = nil
        ) {
            self.uuid = uuid
            self.title = title
            self.notes = notes
            self.isCompleted = isCompleted
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.sortIndex = sortIndex
            self.dueDayKey = dueDayKey
            self.dueMinuteOfDay = dueMinuteOfDay
            self.priorityRaw = priority.rawValue
            self.isFlagged = isFlagged
            self.recurrenceRaw = recurrence?.rawValue
            self.subtasks = []
        }
    }

    @Model
    final class AlarmItem {
        @Attribute(.unique) var uuid: UUID

        var label: String

        var minuteOfDay: Int

        var scheduledWeekdaysMask: Int

        var isEnabled: Bool

        var snoozeEnabled: Bool

        var createdAt: Date

        var sortIndex: Int

        var systemAlarmID: UUID?

        init(
            uuid: UUID = UUID(),
            label: String = "",
            minuteOfDay: Int,
            schedule: WeekdaySet = .everyDay,
            isEnabled: Bool = true,
            snoozeEnabled: Bool = true,
            createdAt: Date = .now,
            sortIndex: Int = 0,
            systemAlarmID: UUID? = nil
        ) {
            self.uuid = uuid
            self.label = label
            self.minuteOfDay = max(0, min(minuteOfDay, 24 * 60 - 1))
            self.scheduledWeekdaysMask = schedule.rawValue
            self.isEnabled = isEnabled
            self.snoozeEnabled = snoozeEnabled
            self.createdAt = createdAt
            self.sortIndex = sortIndex
            self.systemAlarmID = systemAlarmID
        }
    }
}
