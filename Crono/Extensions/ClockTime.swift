import Foundation

/// Formato de hora del reloj, «7:30».
///
/// Existe porque la misma línea estaba escrita en `AlarmItem` y en
/// `ReminderRowView`, y la sección de ciclos de sueño iba a ser la tercera copia.
///
/// No usa `Date.FormatStyle` a propósito: en regiones de 12 horas daría «7:30 AM»,
/// y aquí las horas se muestran a tamaño grande o alineadas en columna — el
/// sufijo desequilibra la fila y rompe la alineación de las cifras.
enum ClockTime {

    /// A partir de minutos desde medianoche.
    static func text(minuteOfDay: Int) -> String {
        let clamped = max(0, min(minuteOfDay, 24 * 60 - 1))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// A partir de un instante.
    static func text(from date: Date, calendar: Calendar = AppCalendar.current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Duración en horas y minutos: «7 h 30 min».
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
