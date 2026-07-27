import Foundation

/// Identificador de un día de calendario en formato `yyyyMMdd` (ej. `20260727`).
///
/// Se usa `Int` en lugar de `Date` porque "¿completé el hábito el día 27?" es una
/// pregunta de día de calendario, no de instante. Un `Date` normalizado a
/// `startOfDay` cambia de valor si el usuario viaja a otra zona horaria, lo que
/// desplazaría registros ya guardados y rompería rachas históricas. Un `Int` es
/// inmune a eso, es indexable por SwiftData y se compara por rangos.
typealias DayKey = Int

/// Calendario único de la app.
///
/// Siempre gregoriano —para que `dayKey` sea un `yyyyMMdd` legible y estable—
/// pero tomando la zona horaria y el primer día de la semana del usuario, de modo
/// que la rejilla del mes se dibuje como espera (lunes primero en España).
enum AppCalendar {
    static var current: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }
}

// MARK: - Date → DayKey

extension Date {
    /// El día de calendario al que pertenece este instante.
    var dayKey: DayKey {
        AppCalendar.current.dayKey(from: self)
    }
}

// MARK: - Conversiones

extension Calendar {
    /// Convierte un instante en su clave de día.
    func dayKey(from date: Date) -> DayKey {
        let parts = dateComponents([.year, .month, .day], from: date)
        // Los tres componentes están garantizados: acabamos de solicitarlos.
        return parts.year! * 10_000 + parts.month! * 100 + parts.day!
    }

    /// Convierte una clave de día en el instante de su medianoche.
    ///
    /// Devuelve `nil` solo si la clave no representa una fecha válida
    /// (por ejemplo `20260230`).
    func date(fromDayKey key: DayKey) -> Date? {
        var parts = DateComponents()
        parts.year = key / 10_000
        parts.month = (key / 100) % 100
        parts.day = key % 100
        return date(from: parts)
    }

    /// Día de la semana (1 = domingo … 7 = sábado) de una clave de día.
    func weekday(fromDayKey key: DayKey) -> Int? {
        guard let date = date(fromDayKey: key) else { return nil }
        return component(.weekday, from: date)
    }

    /// Desplaza una clave de día un número de días, respetando meses y años.
    ///
    /// Es el único camino admitido para recorrer días: restar 1 al `Int`
    /// directamente sería incorrecto en cambios de mes (`20260301 - 1` no es
    /// el 28 de febrero).
    func dayKey(_ key: DayKey, offsetByDays days: Int) -> DayKey? {
        guard let date = date(fromDayKey: key),
              let shifted = self.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return dayKey(from: shifted)
    }

    /// Todas las claves de día de un intervalo, en orden ascendente.
    func dayKeys(from start: DayKey, to end: DayKey) -> [DayKey] {
        guard start <= end else { return [] }
        var keys: [DayKey] = []
        var cursor = start
        while cursor <= end {
            keys.append(cursor)
            guard let next = dayKey(cursor, offsetByDays: 1) else { break }
            cursor = next
        }
        return keys
    }
}

// MARK: - Formato

extension Calendar {
    /// Texto legible de una clave de día, o cadena vacía si la clave es inválida.
    ///
    /// Vive en `Calendar` y no en una extensión de `DayKey`: como `DayKey` es un
    /// alias de `Int`, extenderlo añadiría estos métodos a todos los enteros
    /// de la app y competiría con los `Int.formatted` de Foundation.
    func displayString(forDayKey key: DayKey, style: Date.FormatStyle) -> String {
        guard let date = date(fromDayKey: key) else { return "" }
        return date.formatted(style)
    }
}
