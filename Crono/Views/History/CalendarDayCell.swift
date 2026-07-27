import SwiftUI

/// Una celda del calendario mensual.
///
/// El arco alrededor del número indica qué fracción de los hábitos programados
/// se cumplió ese día. Se dibuja como anillo y no como relleno para que el
/// número siga siendo legible con cualquier nivel de progreso.
struct CalendarDayCell: View {
    private let cell: HistoryViewModel.DayCell
    private let accessibilityLabel: String?

    private let ringWidth: CGFloat = 3

    init(cell: HistoryViewModel.DayCell, accessibilityLabel: String?) {
        self.cell = cell
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        ZStack {
            if cell.state != .blank {
                Circle()
                    .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: ringWidth)

                if cell.fraction > 0 {
                    Circle()
                        .trim(from: 0, to: min(cell.fraction, 1))
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                // Un día perfecto se rellena además del anillo: dos señales
                // distintas para el mismo hecho, no solo un tono más intenso.
                if cell.isPerfect {
                    Circle()
                        .fill(Color.accentColor.opacity(0.16))
                        .padding(ringWidth)
                }
            }

            if let number = cell.dayNumber {
                Text("\(number)")
                    .font(.footnote.weight(cell.state == .today ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            // Hoy lleva contorno además de color, porque el color solo no
            // distingue el día actual para quien no percibe el acento.
            if cell.state == .today {
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(accessibilityLabel ?? "")
    }

    private var numberColor: Color {
        switch cell.state {
        case .blank: .clear
        case .today: .accentColor
        case .future: Color(uiColor: .tertiaryLabel)
        case .past: .primary
        }
    }
}

#Preview("Celdas", traits: .sizeThatFitsLayout) {
    // Las celdas se construyen directamente como `DayCell`, que ya es
    // `Identifiable`. Un array de tuplas recorrido con `enumerated()` obliga al
    // inferidor de tipos a un trabajo desproporcionado para una
    // previsualización, y las previsualizaciones también se compilan.
    let cells: [HistoryViewModel.DayCell] = [
        .init(id: 0, dayKey: 20_260_703, dayNumber: 3, fraction: 0, state: .past),
        .init(id: 1, dayKey: 20_260_704, dayNumber: 4, fraction: 0.33, state: .past),
        .init(id: 2, dayKey: 20_260_705, dayNumber: 5, fraction: 0.66, state: .past),
        .init(id: 3, dayKey: 20_260_706, dayNumber: 6, fraction: 1, state: .past),
        .init(id: 4, dayKey: 20_260_727, dayNumber: 27, fraction: 0.4, state: .today),
        .init(id: 5, dayKey: 20_260_728, dayNumber: 28, fraction: 0, state: .future),
        .init(id: 6, dayKey: nil, dayNumber: nil, fraction: 0, state: .blank)
    ]

    HStack(spacing: 8) {
        ForEach(cells) { cell in
            CalendarDayCell(cell: cell, accessibilityLabel: nil)
                .frame(width: 42)
        }
    }
    .padding()
}
