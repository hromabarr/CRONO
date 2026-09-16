import Foundation

/// Lo que hay que hacer para que una alarma deje de volver.
///
/// ## La distinción que sostiene todo esto
///
/// **Parar no es desarmar.** iOS no deja que una app impida silenciar una
/// alarma, y hace bien: una alarma que no se puede callar es una alarma rota.
/// Lo que sí se puede es que callarla no sea el final — la alarma vuelve a los
/// pocos minutos hasta que se cumple el método de desarme.
///
/// Por eso el usuario siempre tiene el botón de Parar. Lo que decide este tipo
/// es si además hay algo que hacer para que no vuelva.
enum DisarmMethod: Equatable, Hashable, Sendable {
    /// Sin desarme: parar es suficiente. El comportamiento de siempre.
    case stop

    /// Resolver una cuenta sencilla en el teléfono.
    ///
    /// No obliga a levantarse, pero sí a estar despierto. Es el único que
    /// funciona hoy sin cuenta de pago de Apple.
    case arithmetic

    /// Escanear con la cámara un código que vive en otro sitio de la casa.
    ///
    /// Es el único que de verdad obliga a salir de la cama, porque el código
    /// está donde uno lo ponga —el baño, la cafetera— y hay que ir hasta él.
    ///
    /// Sustituye a la pegatina NFC, que necesitaría el entitlement
    /// `com.apple.developer.nfc.readersession.formats` y con él la cuenta de
    /// pago de Apple. La cámara solo pide `NSCameraUsageDescription`.
    ///
    /// Vale cualquier código que la cámara sepa leer, y eso es a propósito: un
    /// QR que genera Crono y se imprime, o directamente el código de barras de
    /// algo que ya viva en ese sitio —el bote de champú, la caja de cereales—.
    /// Lo segundo no obliga a tener impresora, que es la diferencia entre una
    /// función usable y una que se queda sin estrenar.
    ///
    /// Se puede fotografiar y enseñar desde otra pantalla, claro; pero el rival
    /// aquí es uno mismo a las siete de la mañana, no un atacante.
    case scannedCode(value: String)

    // MARK: - Persistencia
    //
    // Se guarda como cadena y no como entero por lo mismo que `RecurrenceRule`:
    // un caso con valor asociado no cabe en un `Int`, y una cadena se lee en el
    // depurador sin tener que descifrarla.

    var rawValue: String {
        switch self {
        case .stop: "stop"
        case .arithmetic: "arithmetic"
        case let .scannedCode(value): "code:\(value)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "stop":
            self = .stop
        case "arithmetic":
            self = .arithmetic
        default:
            guard rawValue.hasPrefix("code:") else { return nil }
            let value = String(rawValue.dropFirst(5))
            // Un código vacío no se puede reconocer, así que guardarlo dejaría
            // una alarma imposible de desarmar.
            guard !value.isEmpty else { return nil }
            self = .scannedCode(value: value)
        }
    }

    // MARK: - Presentación

    /// Si hace falta algo más que pulsar Parar.
    var requiresAction: Bool { self != .stop }

    var label: String {
        switch self {
        case .stop: "Solo parar"
        case .arithmetic: "Resolver una cuenta"
        case .scannedCode: "Escanear un código"
        }
    }

    /// Qué le pasa al usuario si elige esto, dicho sin prometer de más.
    var explanation: String {
        switch self {
        case .stop:
            "La alarma se para y no vuelve."
        case .arithmetic:
            "Podrás pararla, pero volverá hasta que resuelvas una cuenta."
        case .scannedCode:
            "Podrás pararla, pero volverá hasta que escanees tu código."
        }
    }
}
