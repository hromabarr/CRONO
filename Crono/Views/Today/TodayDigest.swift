import Foundation

/// Todo lo que la pantalla Hoy necesita dibujar, ya resuelto.
///
/// Existe para que las subvistas reciban **un** parámetro en lugar de seis. No
/// es solo cosmética: cada argumento de más en una vista es más trabajo para el
/// inferidor de tipos, y esta pantalla ya obligó una vez a partir el archivo en
/// cuatro por esa razón.
///
/// Se calcula una vez arriba y baja hecho. Así `nowMinuteOfDay` y `today` son el
/// mismo valor en toda la pantalla: si cada fila los leyera por su cuenta, dos
/// filas dibujadas a caballo de la medianoche podrían discrepar.
struct TodayDigest {
    /// Hábitos que tocan hoy, en el orden del usuario.
    let scheduledHabits: [Habit]

    /// Tareas que vencen hoy o antes y siguen pendientes, las más urgentes
    /// primero.
    let reminders: [Reminder]

    /// La próxima alarma que sonará, si hay alguna activa.
    let nextAlarm: AlarmItem?

    let today: DayKey
    let nowMinuteOfDay: Int

    /// No hay nada que hacer hoy: ni hábitos, ni tareas.
    ///
    /// La alarma no cuenta. Tener el despertador puesto no es una tarea
    /// pendiente, y si contara, la pantalla nunca diría que el día está libre.
    var isEmpty: Bool {
        scheduledHabits.isEmpty && reminders.isEmpty
    }

    // MARK: - Recorte de tareas

    /// Cuántas tareas caben en el resumen antes de mandar a la pestaña completa.
    ///
    /// Hoy es un resumen. Si vuelca cuarenta tareas deja de serlo y entierra los
    /// hábitos y la alarma que van debajo.
    static let visibleReminderLimit = 4

    var visibleReminders: [Reminder] {
        Array(reminders.prefix(Self.visibleReminderLimit))
    }

    var hiddenReminderCount: Int {
        max(0, reminders.count - Self.visibleReminderLimit)
    }
}
