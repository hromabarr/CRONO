import SwiftUI

/// One accessible button for marking a dated record in routines and history.
struct HabitRecordRow: View {
    let habit: Habit
    let day: DayKey
    let onToggle: () -> Void

    private var completed: Bool { habit.isCompleted(on: day) }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(habit.color.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .foregroundStyle(completed ? .secondary : .primary)
                    if !habit.isActive {
                        Text("Archivado").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(habit.name), \(completed ? "completado" : "sin completar")")
        .accessibilityHint(completed ? "Desmarcar este día" : "Marcar este día")
        .accessibilityAddTraits(completed ? [.isSelected] : [])
        .sensoryFeedback(.success, trigger: completed) { _, new in new }
    }
}
