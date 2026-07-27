import SwiftUI

/// Una celda del calendario mensual.
///
/// El arco alrededor del número indica qué fracción de los hábitos programados
/// se cumplió ese día. Se dibuja como anillo y no como relleno para que el
/// número siga siendo legible con cualquier nivel de progreso.
struct CalendarDayCell: View {
    var cell: HistoryViewModel.DayCell
    var accessibilityLabel: String?

    private let ringWidth: CGFloat = 3

    var body: some View {
        ZStack {
            if cell.state != .blank {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: ringWidth)

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
        case .future: Color(.tertiaryLabel)
        case .past: .primary
        }
    }
}

#Preview("Celdas", traits: .sizeThatFitsLayout) {
    let states: [(HistoryViewModel.DayState, Double, Int?)] = [
        (.past, 0, 3), (.past, 0.33, 4), (.past, 0.66, 5),
        (.past, 1, 6), (.today, 0.4, 27), (.future, 0, 28), (.blank, 0, nil)
    ]

    HStack(spacing: 8) {
        ForEach(Array(states.enumerated()), id: \.offset) { index, item in
            CalendarDayCell(
                cell: .init(
                    id: index,
                    dayKey: item.2 == nil ? nil : 20_260_700 + item.2!,
                    dayNumber: item.2,
                    fraction: item.1,
                    state: item.0
                ),
                accessibilityLabel: nil
            )
            .frame(width: 42)
        }
    }
    .padding()
}
