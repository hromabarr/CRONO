import Foundation
import SwiftData

/// Las consultas de hábitos que usa la interfaz.
///
/// ## Por qué no van escritas en el `@Query` de cada vista
///
/// Un `@Query(filter: #Predicate { ... }, sort: [SortDescriptor(...), ...])` se
/// comprueba como **una sola expresión**: el inicializador de un property
/// wrapper no se puede partir en pasos. Y ahí dentro coinciden las muchas
/// sobrecargas de `Query.init`, las genéricas de `SortDescriptor` sobre key paths
/// opcionales y no opcionales, un literal de array y la expansión de una macro.
///
/// Medido con `-warn-long-expression-type-checking`, ese único `@Query` tardaba
/// **5.390 ms** en comprobar tipos y hacía fallar la compilación del archivo con
/// «unable to type-check this expression in reasonable time». Estaba copiado en
/// las tres pantallas, así que fallaban las tres.
///
/// Aquí el descriptor se construye con sentencias sueltas y tipos anotados, que
/// el compilador comprueba una a una. Además deja de estar duplicado.
enum HabitQueries {

    /// Hábitos activos, en el orden elegido por el usuario.
    static var active: FetchDescriptor<Habit> {
        let predicate = #Predicate<Habit> { $0.archivedAt == nil }
        let order: [SortDescriptor<Habit>] = [
            SortDescriptor(\Habit.sortIndex),
            SortDescriptor(\Habit.createdAt)
        ]

        var descriptor = FetchDescriptor<Habit>(predicate: predicate, sortBy: order)
        // Las pantallas leen `completions` de cada hábito para calcular rachas y
        // progreso; traerlas en la misma consulta evita una carga diferida por
        // hábito.
        descriptor.relationshipKeyPathsForPrefetching = [\.completions]
        return descriptor
    }

    /// Hábitos archivados, los más recientes primero.
    static var archived: FetchDescriptor<Habit> {
        let predicate = #Predicate<Habit> { $0.archivedAt != nil }
        let order: [SortDescriptor<Habit>] = [
            SortDescriptor(\Habit.archivedAt, order: .reverse)
        ]

        return FetchDescriptor<Habit>(predicate: predicate, sortBy: order)
    }
}
