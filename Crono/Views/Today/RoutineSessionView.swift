import SwiftData
import SwiftUI

/// Completion records are the session state, so closing and reopening resumes it.
struct RoutineSessionView: View {
    let routine: HabitRoutine
    let day: DayKey

    @Query(HabitQueries.active) private var activeHabits: [Habit]
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(routine: HabitRoutine, day: DayKey) {
        self.routine = routine
        self.day = day
    }

    private var progress: RoutineProgress { RoutineProgress(routine: routine, habits: activeHabits, day: day) }
    private var habits: [Habit] { progress.habits }
    private var next: Habit? { progress.next }
    private var completedCount: Int { progress.completedCount }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppCalendar.current.displayString(forDayKey: day, style: .dateTime.day().month(.wide)))
                        .foregroundStyle(.secondary)
                    Text("\(completedCount) de \(habits.count) hábitos completados")
                        .font(.headline)
                    ProgressView(value: Double(completedCount), total: Double(max(1, habits.count)))
                        .accessibilityLabel("Progreso de la rutina")
                }

                if let next {
                    nextStep(next)
                } else {
                    Section {
                        ContentUnavailableView(
                            habits.isEmpty ? "Sin hábitos para este día" : "Rutina completada",
                            systemImage: habits.isEmpty ? "calendar" : "checkmark.circle",
                            description: Text(habits.isEmpty ? "Asigna hábitos a esta rutina desde Hábitos." : "Todos los pasos de esta rutina están hechos.")
                        )
                    }
                }

                if !habits.isEmpty {
                    Section {
                        ForEach(habits) { habit in
                            HabitRecordRow(habit: habit, day: day, onToggle: { toggle(habit) })
                        }
                    } header: {
                        Text("Pasos de la rutina")
                    } footer: {
                        Text("Puedes marcar los pasos en otro orden o deshacer una marca. Cada cambio se guarda al tocar.")
                    }
                }
            }
            .navigationTitle(routine.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .habitStoreFailureAlert()
        }
    }

    private func nextStep(_ habit: Habit) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(habit.name)
                    .font(.title2.weight(.semibold))
                if !habit.notes.isEmpty {
                    Text(habit.notes).foregroundStyle(.secondary)
                }
                Button("Marcar y continuar") { toggle(habit) }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Siguiente paso")
        }
    }

    private func toggle(_ habit: Habit) {
        store.toggleCompletion(for: habit, on: day)
    }
}

#Preview("Rutina de mañana") {
    let container = PreviewData.container()
    RoutineSessionView(routine: .morning, day: Date.now.dayKey)
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}
