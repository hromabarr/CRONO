import SwiftUI

struct TodayRoutineCard: View {
    let routine: HabitRoutine
    let habits: [Habit]
    let day: DayKey
    let onOpen: () -> Void

    private var progress: RoutineProgress { RoutineProgress(routine: routine, habits: habits, day: day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: routine.symbolName)
                    .foregroundStyle(Color.accentColor)
                Text("\(progress.completedCount) de \(progress.habits.count) completados")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }

            if let next = progress.next {
                Text("Siguiente: \(next.name)")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Rutina completada")
                    .font(.headline)
            }

            Button(action: onOpen) {
                Text(progress.actionTitle)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("\(progress.actionTitle): \(routine.title)")
        }
        .padding(16)
        .groupedCard()
    }

}
