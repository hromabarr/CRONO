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

    /// Necesario porque las propiedades almacenadas son privadas: el
    /// inicializador sintetizado sería privado y exigiría `activeHabits`.
    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                if activeHabits.isEmpty {
                    EmptyStateView.noHistory
                        .padding(.top, 60)
                } else {
                    HistoryContent(viewModel: viewModel, habits: activeHabits)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Contenido

private struct HistoryContent: View {
    let viewModel: HistoryViewModel
    let habits: [Habit]

    var body: some View {
        VStack(spacing: 0) {
            StatsGridView(
                stats: viewModel.aggregateStats(for: habits),
                monthName: viewModel.monthName
            )

            SectionLabel("Calendario")

            calendar

            Text("El anillo de cada día indica qué fracción de los hábitos programados cumpliste.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
                .padding(.horizontal, 6)

            SectionLabel("Racha por hábito")

            StreakListCard(entries: viewModel.streaks(for: habits))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var calendar: some View {
        MonthCalendarView(
            title: viewModel.monthTitle,
            cells: viewModel.cells(for: habits),
            weekdayInitials: AppCalendar.current.orderedWeekdayInitials,
            canGoForward: viewModel.canGoForward,
            accessibilityLabel: { viewModel.accessibilityLabel(for: $0) },
            onPrevious: viewModel.goToPreviousMonth,
            onNext: viewModel.goToNextMonth
        )
        // El gesto se limita al calendario en lugar de a todo el contenido: un
        // DragGesture sobre el ScrollView entero le disputa el desplazamiento
        // vertical y lo vuelve errático.
        .gesture(monthSwipe)
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
}

private struct StreakListCard: View {
    let entries: [(habit: Habit, streak: Int)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.habit.id) { index, entry in
                HabitStreakRow(habit: entry.habit, streak: entry.streak)
                    .padding(.horizontal, 16)

                if index < entries.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .padding(.vertical, 6)
        .groupedCard()
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
