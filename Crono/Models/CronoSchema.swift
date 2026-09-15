import Foundation
import SwiftData

/// Versión 1 del esquema: la forma que tienen los datos hoy.
///
/// ## Por qué esto existe antes de hacer falta
///
/// Sin un esquema versionado, SwiftData no tiene con qué comparar cuando la
/// forma de los modelos cambia: no hay migración posible y el almacén se
/// invalida, que en un dispositivo real significa que el usuario abre la app y
/// se encuentra sus hábitos, sus tareas y sus alarmas borrados.
///
/// Lo que no se puede hacer es añadirlo *después*. El identificador de versión
/// se graba en el almacén al crearlo; si los primeros usuarios instalan una
/// versión sin él, esos almacenes nacen sin punto de partida y la primera
/// migración no tiene desde dónde arrancar. Por eso va ahora, con el plan
/// vacío: lo que aporta hoy no es la migración, es la marca.
///
/// ## La trampa del día que haya una V2
///
/// Esta enumeración **referencia los tipos vivos** (`Habit`, `Reminder`…) en
/// lugar de copiarlos dentro. Mientras solo haya una versión eso es correcto y
/// evita duplicar cinco modelos para nada.
///
/// En el momento en que haga falta una V2, hay que **congelar la V1 primero**:
/// copiar las definiciones de los modelos dentro de `CronoSchemaV1` tal como
/// están hoy, y solo entonces tocar los tipos vivos. Si se cambia `Habit` sin
/// congelar, `CronoSchemaV1.models` pasa a describir la forma *nueva*, la
/// migración cree que no hay nada que migrar y se aplica en silencio sobre
/// datos que sí cambiaron. Es un fallo que no da error de compilación ni salta
/// en las pruebas: se ve cuando a alguien le faltan los datos.
enum CronoSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// La lista única de modelos de la app.
    ///
    /// Está aquí y no repetida en cada sitio que abre un contenedor porque el
    /// fallo natural es el contrario: añadir un `@Model` nuevo, registrarlo en
    /// la app y olvidarlo en las pruebas o en las previsualizaciones. Compila
    /// igual, y luego falla al guardar con un error que no señala la causa.
    static var models: [any PersistentModel.Type] {
        [Habit.self, HabitCompletion.self, ReminderList.self, Reminder.self, AlarmItem.self]
    }
}

/// Plan de migración del almacén.
///
/// Hoy tiene una sola versión y ninguna etapa, así que no hace nada. Es el
/// gancho: cuando llegue `CronoSchemaV2`, se añade aquí y se declara la etapa
/// que lleva de una a otra —ligera si solo se añaden campos opcionales,
/// personalizada si hay que rellenar o transformar algo.
enum CronoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CronoSchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}

extension Schema {
    /// El esquema de la app, para no volver a escribir la lista de modelos.
    static var crono: Schema { Schema(versionedSchema: CronoSchemaV1.self) }
}
