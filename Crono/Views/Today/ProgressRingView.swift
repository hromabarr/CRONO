import SwiftUI

/// Anillo que representa la fracción de hábitos completados hoy.
struct ProgressRingView: View {
    private let fraction: Double
    private let lineWidth: CGFloat
    private let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Explícito porque hay propiedades almacenadas privadas; el sintetizado
    /// heredaría el `private` y no sería llamable desde otro archivo.
    init(fraction: Double, lineWidth: CGFloat = 11, tint: Color = .accentColor) {
        self.fraction = fraction
        self.lineWidth = lineWidth
        self.tint = tint
    }

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    tint,
                    // El extremo redondeado hace que el arco se lea como una
                    // cinta física y no como un corte de sector.
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                // El trim empieza a las 3 en punto; girar -90° lo lleva arriba,
                // que es donde se espera que arranque un progreso.
                .rotationEffect(.degrees(-90))
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: clamped)
        .accessibilityHidden(true)  // La cifra del centro ya lo comunica.
    }
}

/// Anillo con el porcentaje y el recuento dentro.
struct ProgressRingLabelView: View {
    var fraction: Double
    var percentText: String
    var countText: String
    var tint: Color = .accentColor
    var diameter: CGFloat = 116

    var body: some View {
        ProgressRingView(fraction: fraction, tint: tint)
            .frame(width: diameter, height: diameter)
            .overlay {
                VStack(spacing: 3) {
                    Text(percentText)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        // Las cifras tabulares evitan que el número dé saltos
                        // laterales al pasar de 40 % a 100 %.
                        .monospacedDigit()
                    Text(countText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
    }
}

#Preview("Progresión", traits: .sizeThatFitsLayout) {
    HStack(spacing: 18) {
        ForEach([0.0, 0.25, 0.6, 1.0], id: \.self) { value in
            ProgressRingLabelView(
                fraction: value,
                percentText: "\(Int(value * 100))%",
                countText: "\(Int(value * 5)) de 5",
                diameter: 96
            )
        }
    }
    .padding()
}
