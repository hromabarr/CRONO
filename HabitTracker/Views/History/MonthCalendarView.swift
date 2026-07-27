import SwiftData
import SwiftUI

/// Calendario mensual con el progreso de cada día.
struct MonthCalendarView: View {
    var title: String
    var cells: [HistoryViewModel.DayCell]
    var weekdayInitials: [String]
    var canGoForward: Bool
    var accessibilityLabel: (HistoryViewModel.DayCell) -> String?
    var onPrevious: () -> Void
    var onNext: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdayInitials.indices, id: \.self) { index in
                    Text(weekdayInitials[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            // La cabecera de días ya está implícita en la etiqueta de cada
            // celda ("27 de julio"); leerla suelta solo añade ruido.
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    CalendarDayCell(cell: cell, accessibilityLabel: accessibilityLabel(cell))
                }
            }
        }
        .padding(16)
        .groupedCard()
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                // Los meses en español llegan en minúscula desde el calendario.
                .textCase(nil)

            Spacer()

            HStack(spacing: 6) {
                monthButton(
                    systemImage: "chevron.left",
                    label: "Mes anterior",
                    enabled: true,
                    action: onPrevious
                )
                monthButton(
                    systemImage: "chevron.right",
                    label: "Mes siguiente",
                    enabled: canGoForward,
                    action: onNext
                )
            }
        }
        .padding(.bottom, 12)
    }

    private func monthButton(
        systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

#Preview("Julio 2026") {
    let container = PreviewData.container()
    let viewModel = HistoryViewModel()
    let habits = (try? container.mainContext.fetch(FetchDescriptor<Habit>())) ?? []

    ScrollView {
        MonthCalendarView(
            title: viewModel.monthTitle,
            cells: viewModel.cells(for: habits),
            weekdayInitials: AppCalendar.current.orderedWeekdayInitials,
            canGoForward: viewModel.canGoForward,
            accessibilityLabel: { viewModel.accessibilityLabel(for: $0) },
            onPrevious: {},
            onNext: {}
        )
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .modelContainer(container)
}
