import SwiftUI

/// Apariencia elegida por el usuario.
///
/// Vive en `UserDefaults` y no en SwiftData: es una preferencia de interfaz de
/// este dispositivo, no un dato del dominio. Si algún día se sincroniza el
/// historial entre dispositivos, no tendría sentido arrastrar con él el tema
/// del iPhone.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Sigue el ajuste del sistema. Es el valor por defecto porque respetarlo es
    /// lo que las HIG piden: el usuario ya eligió una vez, en Ajustes.
    case system
    case light
    case dark

    static let storageKey = "appearanceMode"

    var id: String { rawValue }

    /// `nil` significa "no forzar nada": la vista hereda el modo del sistema.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }
}
