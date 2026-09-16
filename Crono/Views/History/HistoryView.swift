import SwiftData
import SwiftUI

/// Pantalla de historial: calendario mensual y estadísticas.
///
/// No trae `NavigationStack` propio: se abre empujada desde Hábitos, así que la
/// pila la aporta esa pantalla. El historial *es* de los hábitos, no una sección
/// al mismo nivel, y sacarlo de la barra de pestañas deja el sitio que necesitan
/// las tareas y las alarmas.
struct HistoryView: View {
    @Query(HabitQueries.all) private var allHabits: [Habit]

    @State private var viewModel = HistoryViewModel()
    @State private var selectedDay: SelectedDay?
    @Environment(\.scenePhase) private var scenePhase

    private struct SelectedDay: Identifiable {
        let id: DayKey
    }

    /// Necesario porque las propiedades almacenadas son privadas: el
    /// inicializador sintetizado sería privado y exigiría `activeHabits`.
    init() {}

    var body: some View {
        ScrollView {
            if allHabits.isEmpty {
                EmptyStateView.noHistory
                    .padding(.top, 60)
            } else {
                HistoryContent(viewModel: viewModel, habits: allHabits, onSelectDay: { selectedDay = SelectedDay(id: $0) })
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Text("Historial"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedDay) { selection in
            HabitDayEditorView(day: selection.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshToday() }
        }
    }
}

// MARK: - Contenido

private struct HistoryContent: View {
    let viewModel: HistoryViewModel
    let habits: [Habit]
    let onSelectDay: (DayKey) -> Void

    var body: some View {
        VStack(spacing: 0) {
            StatsGridView(
                stats: viewModel.aggregateStats(for: habits),
                monthName: viewModel.monthName
            )

            SectionLabel("Calendario")

            calendar

            Text("Toca un día para corregir sus registros. El anillo indica la fracción de hábitos cumplidos e incluye los archivados hasta su fecha de archivo.")
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
            onNext: viewModel.goToNextMonth,
            onSelectDay: onSelectDay
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
    let entries: [HistoryViewModel.StreakEntry]

    private var firstID: UUID? { entries.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                // El separador va delante de cada fila salvo la primera, en vez
                // de detrás de todas menos la última. Es el mismo resultado
                // visual, pero evita necesitar el índice y con ello el
                // `Array(...enumerated())` que atascaba al compilador.
                if entry.id != firstID {
                    Divider().padding(.leading, 42)
                }

                HabitStreakRow(habit: entry.habit, streak: entry.streak)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
        .groupedCard()
    }
}

#Preview("Con historial") {
    let container = PreviewData.container()

    NavigationStack { HistoryView() }
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}

#Preview("Sin historial") {
    let container = PreviewData.emptyContainer()

    NavigationStack { HistoryView() }
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}
