import SwiftData
import SwiftUI

/// Vista que agrupa tareas de todas las listas: «Hoy» y «Con bandera».
///
/// Filtra en Swift sobre las pendientes ya cargadas en lugar de tener una
/// consulta por cada tipo. `dueThrough` compara un `Int?`, y hacerlo dentro de un
/// `#Predicate` obligaría a desenvolverlo a la fuerza; sobre el resultado es
/// aritmética de enteros y no puede fallar.
struct SmartReminderListView: View {
    enum Kind: Hashable {
        case today
        case flagged

        var title: String {
            switch self {
            case .today: "Hoy"
            case .flagged: "Con bandera"
            }
        }

        var symbolName: String {
            switch self {
            case .today: "calendar"
            case .flagged: "flag.fill"
            }
        }

        var tint: Color {
            switch self {
            case .today: .blue
            case .flagged: .orange
            }
        }

        var emptyMessage: String {
            switch self {
            case .today: "No tienes tareas para hoy. Nada que corra prisa."
            case .flagged: "Marca una tarea con bandera para tenerla a mano aquí."
            }
        }
    }

    private let kind: Kind

    @Query(ReminderQueries.pending) private var pending: [Reminder]

    @Environment(ReminderStore.self) private var store

    @State private var editing: Reminder?

    init(kind: Kind) {
        self.kind = kind
    }

    var body: some View {
        Group {
            if reminders.isEmpty {
                EmptyStateView(
                    title: kind.title,
                    message: kind.emptyMessage,
                    systemImage: kind.symbolName
                )
            } else {
                list
            }
        }
        .navigationTitle(Text(kind.title))
        .sheet(item: $editing) { reminder in
            ReminderFormView(mode: .edit(reminder))
        }
    }

    private var list: some View {
        List {
            ForEach(reminders) { reminder in
                row(reminder)
            }
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        Button {
            editing = reminder
        } label: {
            ReminderRowView(
                reminder: reminder,
                tint: reminder.list?.color.color ?? .accentColor,
                today: Date.now.dayKey,
                nowMinuteOfDay: Self.currentMinuteOfDay(),
                onToggle: { store.toggleCompletion(for: reminder) }
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.delete(reminder)
            } label: {
                Label(text: "Eliminar", systemImage: "trash")
            }
        }
    }

    private var reminders: [Reminder] {
        let topLevel = pending.topLevel
        switch kind {
        case .today:
            return topLevel.dueThrough(Date.now.dayKey).byDueDateUndatedLast
        case .flagged:
            var result: [Reminder] = []
            for reminder in topLevel where reminder.isFlagged {
                result.append(reminder)
            }
            return result.byDueDateUndatedLast
        }
    }

    /// Minutos transcurridos hoy, para decidir qué tareas van con retraso.
    ///
    /// No se calcula dentro de la fila: se hace una vez por pantalla y se pasa
    /// hecho, para que no se recalcule en cada redibujado de cada fila.
    static func currentMinuteOfDay(calendar: Calendar = AppCalendar.current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: .now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// `Reminder` no necesita conformidad a `Identifiable` para `.sheet(item:)`: el
// macro `@Model` ya la aporta a través de `PersistentModel`, con el
// `persistentModelID` como identidad. Declararla a mano sería redundante, y
// además fue justo la colisión que obligó a renombrar `Habit.id` a `uuid`.
