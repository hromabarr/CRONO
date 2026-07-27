import SwiftUI

/// Estado sin contenido, construido sobre `ContentUnavailableView`.
///
/// Existe para que los textos vacíos de la app estén todos en un sitio: un
/// estado vacío mal escrito ("Sin datos") deja al usuario sin saber si algo se
/// rompió o si simplemente aún no ha hecho nada.
struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

extension EmptyStateView {
    /// No hay ningún hábito creado todavía.
    static func noHabits(onCreate: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            title: "Sin hábitos todavía",
            message: "Crea tu primer hábito y empieza a registrar los días que lo cumples.",
            systemImage: "checkmark.circle",
            actionTitle: "Crear hábito",
            action: onCreate
        )
    }

    /// Hay hábitos, pero ninguno toca hoy.
    static var nothingToday: EmptyStateView {
        EmptyStateView(
            title: "Hoy no toca nada",
            message: "Ninguno de tus hábitos está programado para hoy. Disfruta del día libre.",
            systemImage: "moon.zzz"
        )
    }

    /// Aún no hay historial que enseñar.
    static var noHistory: EmptyStateView {
        EmptyStateView(
            title: "Sin historial",
            message: "Cuando empieces a marcar hábitos, aquí verás tu progreso día a día.",
            systemImage: "calendar"
        )
    }
}

#Preview("Sin hábitos") {
    EmptyStateView.noHabits {}
}

#Preview("Nada hoy") {
    EmptyStateView.nothingToday
}
