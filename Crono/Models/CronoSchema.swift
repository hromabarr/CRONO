import Foundation
import SwiftData

/// V2 adds an optional routine to Habit. Existing habits stay unassigned.
/// Freeze these definitions before introducing a future V3.
enum CronoSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Habit.self, HabitCompletion.self, ReminderList.self, Reminder.self, AlarmItem.self]
    }
}

enum CronoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CronoSchemaV1.self, CronoSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: CronoSchemaV1.self, toVersion: CronoSchemaV2.self)]
    }
}

extension Schema {
    static var crono: Schema { Schema(versionedSchema: CronoSchemaV2.self) }
}
