import SwiftUI

/// Círculo que se rellena al marcar un hábito.
///
/// El estado se transmite por **forma**, no solo por color: vacío es un contorno,
/// completado es un disco con una marca. Así sigue siendo legible con daltonismo,
/// en escala de grises y bajo filtros de color, donde un cambio de tono
/// desaparece.
struct CompletionToggle: View {
    private let isCompleted: Bool
    private let tint: Color
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// El círculo mide 29 pt, pero el botón ocupa 44: el objetivo táctil mínimo
    /// de las HIG. Sin esto, fallar el toque sería lo normal.
    private let hitTarget: CGFloat = 44
    private let circleSize: CGFloat = 29

    /// Inicializador explícito porque hay propiedades almacenadas privadas: el
    /// que sintetiza Swift heredaría ese `private` y no se podría llamar desde
    /// otro archivo.
    init(isCompleted: Bool, tint: Color, action: @escaping () -> Void) {
        self.isCompleted = isCompleted
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .background(
                        Circle().fill(isCompleted ? tint : .clear)
                    )

                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isCompleted ? 1 : 0.4)
                    .opacity(isCompleted ? 1 : 0)
            }
            .frame(width: circleSize, height: circleSize)
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        // Muelle críticamente amortiguado: sin rebote, porque no hubo un gesto
        // con inercia detrás. Un sobreimpulso aquí se leería como decorativo.
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isCompleted)
        // El acuse háptico va en el mismo evento causal que el visual.
        .sensoryFeedback(.success, trigger: isCompleted) { _, new in new }
    }
}

/// Estilo de botón que responde en el momento de la pulsación.
///
/// El `.plain` del sistema no da acuse visual, y esperar al `touch-up` para
/// reaccionar hace que la interfaz se sienta muerta.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // El cuerpo se delega a una vista anidada porque `@Environment` solo se
        // rellena en tipos que forman parte de la jerarquía de vistas. Un
        // `@Environment` declarado directamente en el `ButtonStyle` compila,
        // pero devuelve siempre el valor por defecto: el ajuste de movimiento
        // reducido se ignoraría sin que nada avisara.
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        private let configuration: ButtonStyleConfiguration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(configuration: ButtonStyleConfiguration) {
            self.configuration = configuration
        }

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.86 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

#Preview("Estados", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 20) {
        ForEach(HabitColor.allCases) { color in
            HStack(spacing: 16) {
                CompletionToggle(isCompleted: false, tint: color.color) {}
                CompletionToggle(isCompleted: true, tint: color.color) {}
                Text(String(localized: color.displayName))
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
