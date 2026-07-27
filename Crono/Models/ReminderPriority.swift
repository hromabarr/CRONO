import Foundation

/// Prioridad de una tarea, con los mismos cuatro niveles que Recordatorios.
///
/// Se persiste el `Int` para poder ordenar por prioridad en una consulta de
/// SwiftData sin traer todas las tareas a memoria.
enum ReminderPriority: Int, CaseIterable, Identifiable, Codable, Sendable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    static func < (lhs: ReminderPriority, rhs: ReminderPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .none: "Ninguna"
        case .low: "Baja"
        case .medium: "Media"
        case .high: "Alta"
        }
    }

    /// Marca de prioridad que precede al título, como en Recordatorios.
    /// Cadena vacía en `none` para no tener que envolverlo en un opcional.
    var marker: String {
        switch self {
        case .none: ""
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }
}
