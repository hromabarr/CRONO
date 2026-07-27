import SwiftUI

/// Paleta cerrada de colores asignables a un hábito.
///
/// Se persiste el `rawValue` (una cadena estable), nunca un `Color`: los tipos de
/// SwiftUI no son persistibles y, más importante, guardar componentes RGB fijaría
/// el color en un modo de apariencia. Al resolver a colores del sistema, cada
/// hábito se adapta solo al Modo Oscuro y respeta los ajustes de contraste.
enum HabitColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case purple

    var id: String { rawValue }

    /// Color del sistema correspondiente, adaptativo por apariencia.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        }
    }

    /// Nombre localizado, usado como etiqueta de accesibilidad del selector.
    ///
    /// El color no puede ser el único portador de información: sin este nombre,
    /// el selector sería inutilizable con VoiceOver o con daltonismo.
    var displayName: LocalizedStringResource {
        switch self {
        case .red: "Rojo"
        case .orange: "Naranja"
        case .yellow: "Amarillo"
        case .green: "Verde"
        case .teal: "Turquesa"
        case .blue: "Azul"
        case .indigo: "Índigo"
        case .purple: "Morado"
        }
    }

    /// Color por defecto de un hábito nuevo.
    static let `default`: HabitColor = .blue
}
