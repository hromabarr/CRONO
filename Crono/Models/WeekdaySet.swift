import Foundation

/// Conjunto de días de la semana en los que un hábito está programado.
///
/// Es un `OptionSet` sobre un `Int` de 7 bits, donde el bit `n` corresponde al
/// `Calendar.weekday` `n + 1` (1 = domingo … 7 = sábado, la convención de
/// Foundation). Se persiste el `rawValue`; el resto de la app manipula el tipo.
///
/// Un hábito "diario" no es un caso especial: es simplemente `.everyDay`, la
/// máscara con los siete bits activos. Así el filtrado de la vista Hoy y el
/// cálculo de rachas tienen un único camino de código en lugar de dos ramas.
struct WeekdaySet: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    init(rawValue: Int) {
        // Se descartan bits fuera de rango para que datos corruptos no
        // produzcan "días" inexistentes al iterar.
        self.rawValue = rawValue & Self.everyDay.rawValue
    }

    static let sunday = WeekdaySet(rawValue: 1 << 0)
    static let monday = WeekdaySet(rawValue: 1 << 1)
    static let tuesday = WeekdaySet(rawValue: 1 << 2)
    static let wednesday = WeekdaySet(rawValue: 1 << 3)
    static let thursday = WeekdaySet(rawValue: 1 << 4)
    static let friday = WeekdaySet(rawValue: 1 << 5)
    static let saturday = WeekdaySet(rawValue: 1 << 6)

    /// Los siete días. Equivale a un hábito diario.
    static let everyDay = WeekdaySet(rawValue: 0b111_1111)

    /// Lunes a viernes.
    static let weekdays: WeekdaySet = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// Sábado y domingo.
    static let weekend: WeekdaySet = [.saturday, .sunday]

    // MARK: - Conversión con Calendar.weekday

    /// Crea un conjunto con un único día, indicado como `Calendar.weekday` (1…7).
    init(weekday: Int) {
        guard (1...7).contains(weekday) else {
            self.init(rawValue: 0)
            return
        }
        self.init(rawValue: 1 << (weekday - 1))
    }

    /// Indica si el día (`Calendar.weekday`, 1…7) pertenece al conjunto.
    func contains(weekday: Int) -> Bool {
        guard (1...7).contains(weekday) else { return false }
        return rawValue & (1 << (weekday - 1)) != 0
    }

    /// Añade o quita un día, devolviendo un conjunto nuevo.
    func toggling(weekday: Int) -> WeekdaySet {
        contains(weekday: weekday)
            ? subtracting(WeekdaySet(weekday: weekday))
            : union(WeekdaySet(weekday: weekday))
    }

    // MARK: - Consulta

    var isEveryDay: Bool { self == .everyDay }

    /// Número de días programados por semana.
    var dayCount: Int { rawValue.nonzeroBitCount }

    /// Los `Calendar.weekday` del conjunto, ordenados según el primer día de la
    /// semana del usuario (lunes primero en España, domingo en EE. UU.).
    var orderedWeekdays: [Int] {
        Self.weekdayOrder.filter { contains(weekday: $0) }
    }

    /// Los siete `Calendar.weekday` en el orden de presentación del usuario.
    static var weekdayOrder: [Int] {
        let first = AppCalendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    // MARK: - Texto

    /// Descripción para mostrar: "Todos los días", "Lun, Mié, Vie"…
    var displayDescription: String {
        if isEveryDay { return String(localized: "Todos los días") }
        if isEmpty { return String(localized: "Sin días") }
        if self == .weekdays { return String(localized: "Días laborables") }
        if self == .weekend { return String(localized: "Fines de semana") }
        return orderedWeekdays
            .map { Self.shortName(forWeekday: $0) }
            .joined(separator: ", ")
    }

    /// Nombre corto localizado de un día ("lun"), tomado del calendario para que
    /// se traduzca con el idioma del sistema sin mantener una tabla propia.
    static func shortName(forWeekday weekday: Int) -> String {
        let symbols = AppCalendar.current.shortWeekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "" }
        return symbols[weekday - 1].capitalized
    }

    /// Nombre completo localizado de un día ("lunes"), para VoiceOver.
    static func fullName(forWeekday weekday: Int) -> String {
        let symbols = AppCalendar.current.weekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "" }
        return symbols[weekday - 1]
    }

    /// Inicial localizada de un día ("L"), para el selector compacto.
    static func initial(forWeekday weekday: Int) -> String {
        String(shortName(forWeekday: weekday).prefix(1))
    }
}
