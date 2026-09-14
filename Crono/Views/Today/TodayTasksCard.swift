import SwiftUI

/// Las tareas que tocan hoy, dentro de la pantalla Hoy.
///
/// Recibe la lista ya recortada: el límite y la cuenta de las que quedan fuera
/// viven en `TodayDigest`, para que la vista no tenga que instanciarse solo para
/// preguntarle cuántas escondió.
///
/// Incluye las atrasadas: una tarea que venció ayer y sigue pendiente es más
/// urgente que una de hoy, y esconderla porque «no es de hoy» sería justo lo
/// contrario de lo que hace falta.
struct TodayTasksCard: View {
    let reminders: [Reminder]
    let today: DayKey
    let nowMinuteOfDay: Int
    let onToggle: (Reminder) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.showsDivider {
                    Divider().padding(.leading, 58)
                }

                ReminderRowView(
                    reminder: row.reminder,
                    tint: row.reminder.list?.color.color ?? .accentColor,
                    today: today,
                    nowMinuteOfDay: nowMinuteOfDay,
                    onToggle: { onToggle(row.reminder) }
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
        .groupedCard()
    }

    /// Fila resuelta, con el separador ya decidido. Mismo patrón que la tarjeta
    /// de hábitos: comparar identificadores dentro del `ForEach` obliga al
    /// inferidor a un trabajo que aquí no hace falta.
    struct Row: Identifiable {
        let reminder: Reminder
        let showsDivider: Bool

        var id: UUID { reminder.uuid }
    }

    private var rows: [Row] {
        var result: [Row] = []
        for reminder in reminders {
            result.append(Row(reminder: reminder, showsDivider: !result.isEmpty))
        }
        return result
    }
}
