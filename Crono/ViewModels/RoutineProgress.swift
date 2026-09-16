import Foundation

/// A routine resumes from saved daily completions, not a separate step index.
struct RoutineProgress {
    let habits: [Habit]
    let day: DayKey

    init(routine: HabitRoutine, habits: [Habit], day: DayKey) {
        self.day = day
        self.habits = habits
            .filter { $0.isActive && $0.routine == routine && $0.isScheduled(on: day) }
            .sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                return $0.createdAt < $1.createdAt
            }
    }

    var next: Habit? { habits.first { !$0.isCompleted(on: day) } }
    var completedCount: Int { habits.filter { $0.isCompleted(on: day) }.count }

    var actionTitle: String {
        if next == nil { return "Revisar rutina" }
        return completedCount == 0 ? "Empezar rutina" : "Continuar rutina"
    }
}
