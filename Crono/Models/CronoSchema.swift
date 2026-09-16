import Foundation
import SwiftData

/// V3 añade a `AlarmItem` el método de desarme y el plan de insistencia.
///
/// Las alarmas que ya existían siguen sin pedir nada: `disarmMethodRaw` se
/// queda en `nil` —que se lee como «solo parar»— y el plan en cero vueltas.
///
/// Congelar estas definiciones antes de introducir una V4.
enum CronoSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

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
/// Un almacén de la V1 recorre las dos etapas en orden, así que no hace falta
/// una etapa V1 → V3.
enum CronoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CronoSchemaV1.self, CronoSchemaV2.self, CronoSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CronoSchemaV1.self, toVersion: CronoSchemaV2.self),
            .lightweight(fromVersion: CronoSchemaV2.self, toVersion: CronoSchemaV3.self)
        ]
    }
}

extension Schema {
    /// El esquema de la app, para no volver a escribir la lista de modelos.
    static var crono: Schema { Schema(versionedSchema: CronoSchemaV3.self) }
}
