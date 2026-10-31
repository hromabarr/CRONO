import SwiftUI

/// El botón de un hábito con cantidad: un anillo que se llena hacia el
/// objetivo, con lo hecho en el centro.
///
/// Mismo tamaño y objetivo táctil que `CompletionToggle`, para que una lista
/// que mezcla los dos tipos no baile. Al cumplir el objetivo se rellena como
/// el círculo de un hábito de sí o no: hecho se ve igual en los dos.
struct QuantityToggle: View {
    private let count: Int
    private let target: Int
    private let tint: Color
    private let action: () -> Void

    private let hitTarget: CGFloat = 44
    private let circleSize: CGFloat = 29

    init(count: Int, target: Int, tint: Color, action: @escaping () -> Void) {
        self.count = count
        self.target = target
        self.tint = tint
        self.action = action
    }

    private var isComplete: Bool { count >= target }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isComplete {
                    Circle().fill(tint)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    QuantityRing(
                        fraction: Double(count) / Double(max(1, target)),
                        tint: tint,
                        size: circleSize
                    )
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: circleSize, height: circleSize)
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.increase, trigger: count)
        .sensoryFeedback(.success, trigger: isComplete) { _, new in new }
    }
}

/// Anillo de progreso con su pista, para una fracción entre 0 y 1.
struct QuantityRing: View {
    let fraction: Double
    let tint: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

#Preview("Cantidades", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        QuantityToggle(count: 0, target: 8, tint: .blue) {}
        QuantityToggle(count: 3, target: 8, tint: .blue) {}
        QuantityToggle(count: 8, target: 8, tint: .blue) {}
    }
    .padding()
}
