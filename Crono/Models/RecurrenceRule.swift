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

// MARK: - Siguiente vencimiento

extension RecurrenceRule {
    /// El siguiente día en que toca, a partir de uno dado.
    ///
    /// Devuelve `nil` si la regla no puede producir otro día — una regla semanal
    /// sin días marcados, o una clave de fecha corrupta.
    ///
    /// Los saltos de mes y año se delegan a `Calendar`, que además **recorta**:
    /// una tarea mensual del día 31 cae en el 28 o 29 en febrero en lugar de
    /// saltarse el mes. Saltárselo sería peor — una tarea mensual que no aparece
    /// en febrero deja de ser mensual.
    func nextDueDayKey(
        after dayKey: DayKey,
        calendar: Calendar = AppCalendar.current
    ) -> DayKey? {
        switch self {
        case .daily:
            return calendar.dayKey(dayKey, offsetByDays: 1)

        case let .weekly(days):
            return Self.nextWeekly(after: dayKey, days: days, calendar: calendar)

        case .monthly:
            return Self.shifting(dayKey, by: .month, calendar: calendar)

        case .yearly:
            return Self.shifting(dayKey, by: .year, calendar: calendar)
        }
    }

    /// El siguiente día de la semana marcado, mirando como mucho una semana.
    ///
    /// Se avanza día a día en lugar de calcular la diferencia con aritmética
    /// modular: son siete iteraciones como máximo y el código se lee sin tener
    /// que confiar en él.
    private static func nextWeekly(
        after dayKey: DayKey,
        days: WeekdaySet,
        calendar: Calendar
    ) -> DayKey? {
        guard !days.isEmpty else { return nil }

        var cursor = dayKey
        for _ in 1...7 {
            guard let next = calendar.dayKey(cursor, offsetByDays: 1),
                  let weekday = calendar.weekday(fromDayKey: next)
            else { return nil }

            cursor = next
            if days.contains(weekday: weekday) { return cursor }
        }
        return nil
    }

    private static func shifting(
        _ dayKey: DayKey,
        by component: Calendar.Component,
        calendar: Calendar
    ) -> DayKey? {
        guard let date = calendar.date(fromDayKey: dayKey),
              let shifted = calendar.date(byAdding: component, value: 1, to: date)
        else { return nil }

        return calendar.dayKey(from: shifted)
    }
}
