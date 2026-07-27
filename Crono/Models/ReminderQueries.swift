import Foundation
import SwiftData

/// Las consultas de tareas que usa la interfaz.
///
/// Igual que `HabitQueries`, los descriptores se construyen aquí con sentencias
/// sueltas y tipos anotados. Escribirlos en línea dentro de un `@Query` los
/// convierte en una sola expresión que el compilador no puede partir, y eso ya
/// costó tumbar tres pantallas.
///
/// ## Por qué ningún predicado toca una relación
///
/// Los predicados se limitan a propiedades escalares —`isCompleted`,
/// `dueDayKey`, `isFlagged`—. Filtrar por relaciones (`parent == nil`,
/// `list.name == ...`) en un `#Predicate` de SwiftData es terreno con aristas, y
/// aquí no hay forma de probarlo antes de que lo vea un compilador. Distinguir
/// tareas de nivel superior de subtareas se hace en Swift, sobre el resultado:
/// para una app de tareas personales el número de filas lo hace irrelevante, y a
/// cambio la consulta es predecible.
enum ReminderQueries {

    /// Todas las listas, en el orden del usuario.
    static var lists: FetchDescriptor<ReminderList> {
        let order: [SortDescriptor<ReminderList>] = [
            SortDescriptor(\ReminderList.sortIndex),
            SortDescriptor(\ReminderList.createdAt)
        ]

        var descriptor = FetchDescriptor<ReminderList>(sortBy: order)
        descriptor.relationshipKeyPathsForPrefetching = [\.reminders]
        return descriptor
    }

    /// Tareas sin completar, por vencimiento y luego por orden manual.
    ///
    /// Las que no tienen fecha van al final: `dueDayKey` es opcional y SwiftData
    /// ordena `nil` al principio, así que el orden se corrige al presentar.
    static var pending: FetchDescriptor<Reminder> {
        let predicate = #Predicate<Reminder> { $0.isCompleted == false }
        let order: [SortDescriptor<Reminder>] = [
            SortDescriptor(\Reminder.dueDayKey),
            SortDescriptor(\Reminder.sortIndex),
            SortDescriptor(\Reminder.createdAt)
        ]

        var descriptor = FetchDescriptor<Reminder>(predicate: predicate, sortBy: order)
        descriptor.relationshipKeyPathsForPrefetching = [\.subtasks, \.list]
        return descriptor
    }

    /// Tareas marcadas con bandera y sin completar.
    static var flagged: FetchDescriptor<Reminder> {
        let predicate = #Predicate<Reminder> { $0.isFlagged && $0.isCompleted == false }
        let order: [SortDescriptor<Reminder>] = [
            SortDescriptor(\Reminder.dueDayKey),
            SortDescriptor(\Reminder.sortIndex)
        ]

        return FetchDescriptor<Reminder>(predicate: predicate, sortBy: order)
    }

    /// Tareas completadas, las más recientes primero.
    static var completed: FetchDescriptor<Reminder> {
        let predicate = #Predicate<Reminder> { $0.isCompleted }
        let order: [SortDescriptor<Reminder>] = [
            SortDescriptor(\Reminder.completedAt, order: .reverse)
        ]

        return FetchDescriptor<Reminder>(predicate: predicate, sortBy: order)
    }

}

// MARK: - Filtros en memoria

extension Array where Element == Reminder {

    /// Solo las de nivel superior; las subtareas se dibujan dentro de su madre.
    var topLevel: [Reminder] {
        var result: [Reminder] = []
        for reminder in self where reminder.parent == nil {
            result.append(reminder)
        }
        return result
    }

    /// Las que vencen hasta un día dado, incluidas las atrasadas.
    ///
    /// Se filtra aquí y no con un `#Predicate` porque comparar un `Int?` dentro
    /// de un predicado obligaría a desenvolverlo a la fuerza o a usar `??`, y
    /// ninguna de las dos cosas puedo comprobarla sin compilador. Sobre el
    /// resultado ya cargado es aritmética de enteros y no puede fallar.
    func dueThrough(_ dayKey: DayKey) -> [Reminder] {
        var result: [Reminder] = []
        for reminder in self {
            guard let due = reminder.dueDayKey, due <= dayKey else { continue }
            result.append(reminder)
        }
        return result
    }

    /// Ordena poniendo al final las que no tienen fecha.
    ///
    /// SwiftData ordena `nil` al principio, y una tarea sin vencimiento no debe
    /// encabezar una lista ordenada por urgencia.
    var byDueDateUndatedLast: [Reminder] {
        sorted { lhs, rhs in
            switch (lhs.dueDayKey, rhs.dueDayKey) {
            case let (left?, right?):
                if left != right { return left < right }
                return (lhs.dueMinuteOfDay ?? 0) < (rhs.dueMinuteOfDay ?? 0)
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return lhs.sortIndex < rhs.sortIndex
            }
        }
    }
}
