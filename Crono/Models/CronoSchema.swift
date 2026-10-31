import Foundation
import SwiftData

/// V4 añade los hábitos con cantidad y el sonido de las alarmas.
///
/// - `Habit.targetCount` y `Habit.unit`: el objetivo del día, «8 vasos».
/// - `HabitCompletion.count`: cuánto se hizo ese día.
/// - `AlarmItem.soundRaw` y `followUpSoundRaw`: el sonido de la alarma y el
///   de sus vueltas.
///
/// Todo lo que ya existía queda como antes: objetivo 1, cantidad 1 —cada
/// registro antiguo era un «hecho»— y el sonido del sistema.
///
/// Congelar estas definiciones antes de introducir una V5.
enum CronoSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Habit.self, HabitCompletion.self, ReminderList.self, Reminder.self, AlarmItem.self]
    }
}

/// Plan de migración del almacén.
///
/// Las etapas son ligeras porque cada versión solo **añade** propiedades, y
/// todas traen valor por defecto: `nil` las opcionales, y el suyo escrito en la
/// declaración las que no lo son. SwiftData rellena las filas existentes con
/// eso sin que haga falta escribir una transformación.
///
/// Un almacén de la V1 recorre todas las etapas en orden, así que no hace falta
/// una etapa directa a la versión actual.
enum CronoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CronoSchemaV1.self, CronoSchemaV2.self, CronoSchemaV3.self, CronoSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CronoSchemaV1.self, toVersion: CronoSchemaV2.self),
            .lightweight(fromVersion: CronoSchemaV2.self, toVersion: CronoSchemaV3.self),
            .lightweight(fromVersion: CronoSchemaV3.self, toVersion: CronoSchemaV4.self)
        ]
    }
}

extension Schema {
    /// El esquema de la app, para no volver a escribir la lista de modelos.
    static var crono: Schema { Schema(versionedSchema: CronoSchemaV4.self) }
}
