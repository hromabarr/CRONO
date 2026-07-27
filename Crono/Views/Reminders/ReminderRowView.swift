import SwiftUI

/// Fila de una tarea.
struct ReminderRowView: View {
    private let reminder: Reminder
    private let tint: Color
    private let today: DayKey
    private let nowMinuteOfDay: Int
    private let onToggle: () -> Void

    init(
        reminder: Reminder,
        tint: Color,
        today: DayKey,
        nowMinuteOfDay: Int,
        onToggle: @escaping () -> Void
    ) {
        self.reminder = reminder
        self.tint = tint
        self.today = today
        self.nowMinuteOfDay = nowMinuteOfDay
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompletionToggle(
                isCompleted: reminder.isCompleted,
                tint: tint,
                action: onToggle
            )
            .padding(.leading, -6)
            .padding(.vertical, -6)

            VStack(alignment: .leading, spacing: 3) {
                titleLine
                if let detail { detailLine(detail) }
            }

            Spacer(minLength: 0)

            if reminder.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(reminder.isCompleted ? "Toca para desmarcar" : "Toca para completar")
        .accessibilityAddTraits(reminder.isCompleted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Alternar", onToggle)
    }

    // MARK: - Título

    private var titleLine: some View {
        HStack(spacing: 5) {
            if !reminder.priority.marker.isEmpty {
                // La marca de prioridad va delante del título, como en
                // Recordatorios, y en el color de acento para que se lea como
                // una etiqueta y no como parte del texto.
                Text(reminder.priority.marker)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(reminder.title)
                .font(.body)
                .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                .strikethrough(reminder.isCompleted, color: .secondary)
        }
    }

    // MARK: - Segunda línea

    /// Vencimiento, subtareas y nota, en una sola línea separada por puntos.
    ///
    /// Se compone como texto y no como vistas encadenadas porque son fragmentos
    /// opcionales: montarlo con condicionales dentro de un `HStack` deja huecos y
    /// separadores sueltos según qué falte.
    private var detail: String? {
        var parts: [String] = []

        if let dueText { parts.append(dueText) }

        let progress = reminder.subtaskProgress
        if !progress.isEmpty { parts.append(progress.text) }

        let notes = reminder.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { parts.append(notes) }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func detailLine(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isOverdue ? Color.red : Color.secondary)
            .lineLimit(2)
    }

    private var isOverdue: Bool {
        reminder.isOverdue(today: today, nowMinuteOfDay: nowMinuteOfDay)
    }

    /// Texto del vencimiento: «Hoy», «Ayer», «Mañana» o la fecha.
    ///
    /// Los nombres relativos son los que el usuario usa al pensar. «28 de julio»
    /// obliga a calcular si eso es hoy; «Mañana» no.
    private var dueText: String? {
        guard let dueDayKey else { return nil }
        let calendar = AppCalendar.current

        var label: String
        if dueDayKey == today {
            label = "Hoy"
        } else if dueDayKey == calendar.dayKey(today, offsetByDays: -1) {
            label = "Ayer"
        } else if dueDayKey == calendar.dayKey(today, offsetByDays: 1) {
            label = "Mañana"
        } else {
            label = calendar.displayString(forDayKey: dueDayKey, style: .dateTime.day().month(.abbreviated))
        }

        if let minute = reminder.dueMinuteOfDay {
            label += " a las \(Self.timeText(minute))"
        }
        return label
    }

    private var dueDayKey: DayKey? { reminder.dueDayKey }

    static func timeText(_ minuteOfDay: Int) -> String {
        let hours = minuteOfDay / 60
        let minutes = minuteOfDay % 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if reminder.priority != .none { parts.append("Prioridad \(reminder.priority.label.lowercased())") }
        parts.append(reminder.title)
        parts.append(reminder.isCompleted ? "completada" : "sin completar")
        if isOverdue { parts.append("atrasada") }
        if let dueText { parts.append("vence \(dueText)") }
        if reminder.isFlagged { parts.append("con bandera") }
        return parts.joined(separator: ", ")
    }
}
