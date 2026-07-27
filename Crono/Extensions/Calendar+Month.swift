import Foundation

/// Un mes concreto de un año concreto.
///
/// Se usa en lugar de un `Date` para representar "el mes visible": un `Date`
/// obligaría a elegir arbitrariamente un día dentro del mes y abriría la puerta
/// a errores de comparación entre el día 1 y el 15 del mismo mes.
struct MonthIdentifier: Hashable, Sendable, Comparable {
    var year: Int
    var month: Int

    static func < (lhs: MonthIdentifier, rhs: MonthIdentifier) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

extension Calendar {
    // MARK: - Conversión

    func monthIdentifier(from dayKey: DayKey) -> MonthIdentifier {
        MonthIdentifier(year: dayKey / 10_000, month: (dayKey / 100) % 100)
    }

    /// Clave de día de un día concreto del mes. `nil` si el día no existe en ese
    /// mes (por ejemplo el 31 de febrero).
    ///
    /// Se apoya en `date(fromDayKey:)`, que ya rechaza las fechas imposibles con
    /// una comprobación de ida y vuelta. Antes duplicaba aquí esa validación
    /// mientras `date(fromDayKey:)` no la tenía, que es justo el descuadre que
    /// destapó el test del 30 de febrero.
    func dayKey(in month: MonthIdentifier, day: Int) -> DayKey? {
        guard (1...31).contains(day) else { return nil }
        let candidate = month.year * 10_000 + month.month * 100 + day
        return date(fromDayKey: candidate) == nil ? nil : candidate
    }

    /// Primer día del mes como instante, si el mes es válido.
    private func startOfMonth(_ month: MonthIdentifier) -> Date? {
        var parts = DateComponents()
        parts.year = month.year
        parts.month = month.month
        parts.day = 1
        return date(from: parts)
    }

    // MARK: - Geometría del mes

    /// Número de días del mes.
    func numberOfDays(in month: MonthIdentifier) -> Int {
        guard let start = startOfMonth(month),
              let range = range(of: .day, in: .month, for: start)
        else { return 0 }
        return range.count
    }

    /// Cuántas celdas vacías van antes del día 1 en la rejilla.
    ///
    /// Depende del primer día de la semana del usuario: el mismo mes empieza con
    /// dos huecos si la semana arranca en lunes y con tres si arranca en domingo.
    func leadingBlankDays(in month: MonthIdentifier) -> Int {
        guard let start = startOfMonth(month) else { return 0 }
        let weekday = component(.weekday, from: start)
        return (weekday - firstWeekday + 7) % 7
    }

    /// Desplaza un mes, cruzando el cambio de año correctamente.
    func month(_ month: MonthIdentifier, offsetByMonths offset: Int) -> MonthIdentifier {
        guard let start = startOfMonth(month),
              let shifted = date(byAdding: .month, value: offset, to: start)
        else { return month }
        return monthIdentifier(from: dayKey(from: shifted))
    }

    // MARK: - Texto

    /// Nombre del mes con año: "julio 2026".
    func monthTitle(_ month: MonthIdentifier) -> String {
        guard let start = startOfMonth(month) else { return "" }
        return start.formatted(.dateTime.month(.wide).year())
    }

    /// Solo el nombre del mes: "julio".
    ///
    /// Existe como método propio en lugar de partir `monthTitle` por espacios:
    /// ese truco funciona en español y se rompe en cuanto el formato del idioma
    /// coloca el año delante o usa otro separador.
    func monthName(_ month: MonthIdentifier) -> String {
        guard let start = startOfMonth(month) else { return "" }
        return start.formatted(.dateTime.month(.wide))
    }

    /// Iniciales de los días de la semana en el orden de presentación del
    /// usuario, para la cabecera del calendario.
    var orderedWeekdayInitials: [String] {
        WeekdaySet.weekdayOrder.map { WeekdaySet.initial(forWeekday: $0) }
    }
}
