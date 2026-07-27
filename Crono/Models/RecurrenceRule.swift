import Foundation

/// Cada cuánto se repite una tarea.
///
/// Se persiste como cadena y no como caso de enum con datos asociados, porque
/// `.weekly` lleva un conjunto de días dentro y SwiftData no almacena enums con
/// carga útil sin envolverlos. El formato es legible a propósito —`weekly:42`—
/// para que un volcado de la base se pueda leer sin descifrar nada.
/// `Hashable` es obligatorio, no decorativo: la regla se usa como `tag` de un
/// `Picker`, y las etiquetas de selección tienen que ser hashables.
enum RecurrenceRule: Equatable, Hashable, Sendable {
    case daily
    /// Semanal en los días indicados. Reutiliza `WeekdaySet`, el mismo tipo con
    /// el que se programan los hábitos: la pregunta «qué días de la semana» es
    /// idéntica aunque las dos funciones sean independientes.
    case weekly(WeekdaySet)
    /// Mensual, el mismo día del mes que el vencimiento original.
    case monthly
    case yearly

    // MARK: - Persistencia

    var rawValue: String {
        switch self {
        case .daily: "daily"
        case let .weekly(days): "weekly:\(days.rawValue)"
        case .monthly: "monthly"
        case .yearly: "yearly"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "daily": self = .daily
        case "monthly": self = .monthly
        case "yearly": self = .yearly
        default:
            // `weekly:<máscara>`
            let parts = rawValue.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0] == "weekly",
                  let mask = Int(parts[1])
            else { return nil }
            self = .weekly(WeekdaySet(rawValue: mask))
        }
    }

    // MARK: - Texto

    var label: String {
        switch self {
        case .daily: "Cada día"
        case let .weekly(days):
            days.isEveryDay ? "Cada día" : "Cada semana: \(days.displayDescription)"
        case .monthly: "Cada mes"
        case .yearly: "Cada año"
        }
    }
}
