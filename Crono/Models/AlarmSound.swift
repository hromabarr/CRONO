import Foundation

/// El sonido con el que suena una alarma.
///
/// Los archivos los genera `design/sonidos/generar_sonidos.py` y van en el
/// paquete de la app. El valor en bruto es lo que se guarda en
/// `AlarmItem.soundRaw`: `""` es el sonido del sistema, que es lo que tenían
/// todas las alarmas antes de poder elegir.
enum AlarmSound: String, CaseIterable, Identifiable, Sendable {
    case system = ""
    case pulse = "pulso"
    case bell = "campana"
    case siren = "sirena"
    case beep = "pitido"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Del sistema"
        case .pulse: "Pulso"
        case .bell: "Campana"
        case .siren: "Sirena"
        case .beep: "Pitido"
        }
    }

    /// El archivo en el paquete, o `nil` para el del sistema.
    var fileName: String? {
        self == .system ? nil : "\(rawValue).wav"
    }

    /// Un valor guardado que no se conozca —de una versión más nueva, o
    /// dañado— suena con el del sistema: mejor un sonido que ninguno.
    init(stored raw: String) {
        self = AlarmSound(rawValue: raw) ?? .system
    }

    /// El de las vueltas al crear una alarma con desarme. Más molesto que el
    /// de la principal a propósito: es el que tiene que sacarte de la cama.
    static let defaultFollowUp: AlarmSound = .siren
}

extension AlarmItem {
    var sound: AlarmSound {
        get { AlarmSound(stored: soundRaw) }
        set { soundRaw = newValue.rawValue }
    }

    var followUpSound: AlarmSound {
        get { AlarmSound(stored: followUpSoundRaw) }
        set { followUpSoundRaw = newValue.rawValue }
    }
}
