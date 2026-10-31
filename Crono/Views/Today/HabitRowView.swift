import SwiftData
import SwiftUI

/// Fila de un hábito en la lista de hoy.
///
/// Los hábitos con cantidad cambian el círculo por un anillo que se va
/// llenando: tocar suma uno, y el menú contextual resta.
struct HabitRowView: View {
    var habit: Habit
    var isCompleted: Bool
    var accessibilityLabel: String
    var accessibilityHint: String
    var onToggle: () -> Void
    /// El día que muestra la fila. Hace falta para leer y restar la cantidad.
    var day: DayKey = Date.now.dayKey

    @Environment(HabitStore.self) private var store: HabitStore?

    var body: some View {
        HStack(spacing: 14) {
            toggle
                // El botón ya trae su propio objetivo de 44 pt; este margen
                // negativo recupera el espacio sobrante para que la fila no
                // quede holgada.
                .padding(.leading, -6)
                .padding(.vertical, -6)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.body)
                    // Atenuar lo hecho da al usuario un frente de trabajo claro:
                    // lo que queda por hacer es lo que resalta.
                    .foregroundStyle(isCompleted ? .secondary : .primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // La fila entera se expone como un solo control: sin esto, VoiceOver
        // leería el botón y el texto como dos elementos sin relación.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isCompleted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: habit.hasQuantityGoal ? "Sumar uno" : "Alternar", onToggle)
        .accessibilityAction(named: "Restar uno") {
            if habit.hasQuantityGoal { store?.decrement(habit, on: day, today: day) }
        }
        .contextMenu {
            if habit.hasQuantityGoal, let store, habit.count(on: day) > 0 {
                Button("Restar uno", systemImage: "minus") {
                    store.decrement(habit, on: day, today: day)
                }
            }
        }
    }

    @ViewBuilder
    private var toggle: some View {
        if habit.hasQuantityGoal {
            QuantityToggle(
                count: habit.count(on: day),
                target: habit.targetCount,
                tint: habit.color.color,
                action: onToggle
            )
        } else {
            CompletionToggle(
                isCompleted: isCompleted,
                tint: habit.color.color,
                action: onToggle
            )
        }
    }

    private var subtitle: String? {
        let notes = habit.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // En los de cantidad, lo primero que se busca es cuánto falta.
        let schedule = habit.hasQuantityGoal
            ? habit.progressText(on: day)
            : habit.schedule.displayDescription

        if notes.isEmpty { return schedule }
        return "\(notes) · \(schedule)"
    }
}

#Preview("Filas") {
    let container = PreviewData.container()
    let habits = (try? container.mainContext.fetch(FetchDescriptor<Habit>())) ?? []
    let sample = Array(habits.prefix(4))

    List {
        ForEach(sample) { habit in
            HabitRowView(
                habit: habit,
                // Se alternan marcados y sin marcar buscando la posición por
                // `id`, sin `enumerated()` ni `firstIndex(of:)`: el primero le
                // cuesta al inferidor más de lo que vale y el segundo exigiría
                // que `Habit` fuese `Equatable`, que en una clase `@Model` no
                // está garantizado.
                isCompleted: (sample.firstIndex { $0.uuid == habit.uuid } ?? 0).isMultiple(of: 2),
                accessibilityLabel: habit.name,
                accessibilityHint: "Toca para marcar",
                onToggle: {}
            )
        }
    }
    .modelContainer(container)
}
