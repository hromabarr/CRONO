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

    /// Acercar el teléfono a una pegatina NFC concreta.
    ///
    /// Es el único que de verdad obliga a salir de la cama, porque la pegatina
    /// está donde uno la pegue —el baño, la cafetera— y hay que ir hasta ella.
    ///
    /// Guarda el identificador de la pegatina, no su contenido: el UID viene de
    /// fábrica y no se puede reescribir, mientras que lo que hay escrito dentro
    /// sí. Se puede clonar con otro aparato, claro; pero el rival aquí es uno
    /// mismo a las siete de la mañana, no un atacante.
    case tag(uid: String)

    // MARK: - Persistencia
    //
    // Se guarda como cadena y no como entero por lo mismo que `RecurrenceRule`:
    // un caso con valor asociado no cabe en un `Int`, y una cadena se lee en el
    // depurador sin tener que descifrarla.

    var rawValue: String {
        switch self {
        case .stop: "stop"
        case .arithmetic: "arithmetic"
        case let .tag(uid): "tag:\(uid)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "stop":
            self = .stop
        case "arithmetic":
            self = .arithmetic
        default:
            guard rawValue.hasPrefix("tag:") else { return nil }
            let uid = String(rawValue.dropFirst(4))
            // Una pegatina sin identificador no se puede reconocer, así que
            // guardarla dejaría una alarma imposible de desarmar.
            guard !uid.isEmpty else { return nil }
            self = .tag(uid: uid)
        }
    }

    // MARK: - Presentación

    /// Si hace falta algo más que pulsar Parar.
    var requiresAction: Bool { self != .stop }

    var label: String {
        switch self {
        case .stop: "Solo parar"
        case .arithmetic: "Resolver una cuenta"
        case .tag: "Escanear la pegatina"
        }
    }

    /// Qué le pasa al usuario si elige esto, dicho sin prometer de más.
    var explanation: String {
        switch self {
        case .stop:
            "La alarma se para y no vuelve."
        case .arithmetic:
            "Podrás pararla, pero volverá hasta que resuelvas una cuenta."
        case .tag:
            "Podrás pararla, pero volverá hasta que acerques el teléfono a tu pegatina."
        }
    }
}
