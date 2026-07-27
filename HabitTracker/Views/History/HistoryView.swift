import SwiftData
import SwiftUI

/// Pantalla de historial: calendario mensual y estadísticas.
struct HistoryView: View {
    @Query(
        filter: #Predicate<Habit> { $0.archivedAt == nil },
        sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]
    )
    private var activeHabits: [Habit]

    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if activeHabits.isEmpty {
                    EmptyStateView.noHistory
                        .padding(.top, 60)
                } else {
                    content
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private var content: some View {
        let stats = viewModel.aggregateStats(for: activeHabits)
        let streaks = viewModel.streaks(for: activeHabits)

        VStack(spacing: 0) {
            StatsGridView(stats: stats, monthName: viewModel.monthName)

            sectionLabel("Calendario")

            MonthCalendarView(
                title: viewModel.monthTitle,
                cells: viewModel.cells(for: activeHabits),
                weekdayInitials: AppCalendar.current.orderedWeekdayInitials,
                canGoForward: viewModel.canGoForward,
                accessibilityLabel: { viewModel.accessibilityLabel(for: $0) },
                onPrevious: viewModel.goToPreviousMonth,
                onNext: viewModel.goToNextMonth
            )
            // El gesto se limita al calendario en lugar de a todo el contenido:
            // un DragGesture sobre el ScrollView entero le disputa el
            // desplazamiento vertical y lo vuelve errático.
            .gesture(monthSwipe)

            Text("El anillo de cada día indica qué fracción de los hábitos programados cumpliste.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
                .padding(.horizontal, 6)

            sectionLabel("Racha por hábito")

            VStack(spacing: 0) {
                ForEach(Array(streaks.enumerated()), id: \.element.habit.id) { index, entry in
                    HabitStreakRow(habit: entry.habit, streak: entry.streak)
                        .padding(.horizontal, 16)

                    if index < streaks.count - 1 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
            .padding(.vertical, 6)
            .groupedCard()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    /// Cambiar de mes deslizando sobre el calendario.
    ///
    /// Solo se acepta si el recorrido es claramente horizontal; en caso
    /// contrario el usuario está intentando desplazar la página.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5
                else { return }

                if value.translation.width > 0 {
                    viewModel.goToPreviousMonth()
                } else {
                    viewModel.goToNextMonth()
                }
            }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .padding(.horizontal, 4)
    }
}

#Preview("Con historial") {
    let container = PreviewData.container()

    HistoryView()
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}

#Preview("Sin historial") {
    let container = PreviewData.emptyContainer()

    HistoryView()
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}
