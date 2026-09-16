import SwiftData
import SwiftUI

struct HabitDayEditorView: View {
    let day: DayKey

    @Query(HabitQueries.all) private var allHabits: [Habit]
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(day: DayKey) { self.day = day }

    private var habits: [Habit] {
        allHabits.filter { $0.isScheduled(on: day) || $0.isCompleted(on: day) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppCalendar.current.displayString(forDayKey: day, style: .dateTime.weekday(.wide).day().month(.wide).year()))
                        .font(.headline)
                }
                if day > Date.now.dayKey {
                    ContentUnavailableView("Este día aún no ha llegado", systemImage: "calendar")
                } else if habits.isEmpty {
                    ContentUnavailableView(
                        "Sin hábitos para este día",
                        systemImage: "calendar",
                        description: Text("Aquí aparecen los hábitos programados y los registros que ya guardaste.")
                    )
                } else {
                    Section {
                        ForEach(habits) { habit in
                            HabitRecordRow(habit: habit, day: day) {
                                store.toggleCompletion(for: habit, on: day)
                            }
                        }
                    } header: {
                        Text("Hábitos")
                    } footer: {
                        Text("Toca para marcar o desmarcar. Los cambios se guardan al instante y actualizan el historial. La programación actual determina qué hábitos aparecen sin registro.")
                    }
                }
            }
            .navigationTitle("Corregir registros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .habitStoreFailureAlert()
        }
    }
}

#Preview("Corregir ayer") {
    let container = PreviewData.container()
    let yesterday = AppCalendar.current.dayKey(Date.now.dayKey, offsetByDays: -1) ?? Date.now.dayKey
    HabitDayEditorView(day: yesterday)
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}
