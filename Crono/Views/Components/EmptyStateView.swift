import SwiftUI

/// Estado sin contenido, construido sobre `ContentUnavailableView`.
///
/// Existe para que los textos vacíos de la app estén todos en un sitio: un
/// estado vacío mal escrito ("Sin datos") deja al usuario sin saber si algo se
/// rompió o si simplemente aún no ha hecho nada.
///
/// ## Por qué los tipos están anotados a mano
///
/// `ContentUnavailableView` tiene tres parámetros genéricos, uno de sus cierres
/// lleva un condicional y `Label(_:systemImage:)` con `String` tiene varias
/// sobrecargas. Juntando todo, el inferidor de tipos de Swift se rinde con un
/// «unable to type-check this expression in reasonable time». Declarar el tipo
/// de cada trozo corta esa combinatoria de raíz.
struct EmptyStateView: View {
    private let title: String
    private let message: String
    private let systemImage: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    init(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            labelView
        } description: {
            Text(message)
        } actions: {
            actionsView
        }
    }

    /// Tipo explícito: sin él, `Label` tiene que elegir entre sus sobrecargas
    /// de `LocalizedStringKey` y `StringProtocol` dentro de un genérico.
    private var labelView: Label<Text, Image> {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
    }

    @ViewBuilder
    private var actionsView: some View {
        if let actionTitle, let action {
            Button(action: action) {
                Text(actionTitle)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Estados concretos de la app

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
