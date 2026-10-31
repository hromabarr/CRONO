import SwiftUI

/// One accessible button for marking a dated record in routines and history.
///
/// En los hábitos con cantidad, tocar suma uno y el menú contextual resta.
struct HabitRecordRow: View {
    let habit: Habit
    let day: DayKey
    let onToggle: () -> Void

    @Environment(HabitStore.self) private var store: HabitStore?

    private var completed: Bool { habit.isCompleted(on: day) }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                if habit.hasQuantityGoal {
                    QuantityRing(fraction: habit.fraction(on: day), tint: habit.color.color, size: 26)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(habit.color.color)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .foregroundStyle(completed ? .secondary : .primary)
                    if habit.hasQuantityGoal {
                        Text(habit.progressText(on: day))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
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
        .contextMenu {
            if habit.hasQuantityGoal, let store, habit.count(on: day) > 0 {
                Button("Restar uno", systemImage: "minus") { store.decrement(habit, on: day) }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAction(named: "Restar uno") {
            if habit.hasQuantityGoal { store?.decrement(habit, on: day) }
        }
        .accessibilityAddTraits(completed ? [.isSelected] : [])
        .sensoryFeedback(.success, trigger: completed) { _, new in new }
    }

    private var accessibilityLabel: String {
        if habit.hasQuantityGoal {
            return "\(habit.name), \(habit.progressText(on: day))"
        }
        return "\(habit.name), \(completed ? "completado" : "sin completar")"
    }

    private var accessibilityHint: String {
        if habit.hasQuantityGoal { return "Suma uno a este día" }
        return completed ? "Desmarcar este día" : "Marcar este día"
    }
}
