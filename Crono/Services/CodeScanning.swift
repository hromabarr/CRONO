import Foundation

/// Un código leído por la cámara.
struct ScannedCode: Equatable, Sendable {
    /// El contenido tal y como lo devolvió el lector.
    let value: String

    /// Qué clase de código era. Solo informativo: el emparejado va por el
    /// contenido, no por el formato.
    let symbology: String
}

/// Quien sabe leer códigos con la cámara.
///
/// Mismo aislamiento que `AlarmScheduling` y `ReminderNotifying`, y por la misma
/// razón: la cámara no existe en el simulador, así que nada de lo que se puede
/// probar en CI debe depender de este protocolo. Lo que sí se prueba es la
/// decisión de si un código vale, que vive en `DisarmCode`.
@MainActor
protocol CodeScanning {
    /// Si el aparato tiene cámara utilizable.
    var isAvailable: Bool { get }

    /// Si la cámara puede encender la linterna.
    ///
    /// No es un detalle menor: a las siete menos cuarto el baño está a oscuras,
    /// y un lector que no ilumina es un lector que no lee justo los días que
    /// importan.
    var hasTorch: Bool { get }

    func requestAuthorization() async -> Bool
}

/// Implementación que no toca la cámara. Para pruebas y previsualizaciones.
@MainActor
final class NoopCodeScanner: CodeScanning {
    var isAvailable: Bool
    var hasTorch: Bool

    init(isAvailable: Bool = true, hasTorch: Bool = true) {
        self.isAvailable = isAvailable
        self.hasTorch = hasTorch
    }

    func requestAuthorization() async -> Bool { isAvailable }
}

/// Las reglas de qué código sirve para desarmar.
///
/// Está separado del lector porque es la parte que decide, y la que puede
/// equivocarse de las dos maneras caras: dejar pasar un código que no es —y la
/// alarma se desarma sola— o rechazar el bueno, que deja al usuario encerrado
/// fuera de su propia alarma con el móvil sonando.
enum DisarmCode {

    /// Longitud del secreto que genera Crono para los QR imprimibles.
    ///
    /// Veintidós caracteres de un alfabeto de 32 son unos 110 bits. Es mucho más
    /// de lo que hace falta contra el adversario real, pero un QR no se lee a
    /// mano y los caracteres no cuestan nada.
    static let secretLength = 22

    /// Alfabeto sin los caracteres que se confunden al leerlos: fuera el cero y
    /// la O, y fuera el uno, la I y la L.
    ///
    /// El QR lo lee la cámara, pero el secreto acaba impreso en un papel que
    /// alguien puede tener que teclear si algo falla, y en las tipografías de
    /// palo seco la L mayúscula y el uno se parecen demasiado.
    ///
    /// Quedan 31 caracteres, que no es potencia de dos; da igual, porque
    /// `randomElement()` reparte uniforme sea cual sea el tamaño. Y 22 de ellos
    /// siguen siendo unos 109 bits.
    private static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    /// Un secreto nuevo para una pegatina imprimible.
    static func makeSecret() -> String {
        String((0..<secretLength).map { _ in alphabet.randomElement() ?? "X" })
    }

    /// Deja un código leído como se va a guardar y comparar.
    ///
    /// Solo recorta espacios y saltos: algunos lectores añaden un salto final.
    /// **No** se tocan mayúsculas ni ceros a la izquierda a propósito — normalizar
    /// de más acerca códigos distintos, y un falso positivo aquí significa que la
    /// alarma se desarma con el bote equivocado.
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Si un código sirve para guardarlo como método de desarme.
    static func isUsable(_ raw: String) -> Bool {
        !normalize(raw).isEmpty
    }

    /// Si lo escaneado desarma esta alarma.
    ///
    /// Devuelve `false` para cualquier método que no sea un código: una alarma
    /// que se desarma con la cuenta no debe desarmarse enfocando algo con la
    /// cámara.
    static func matches(_ scanned: String, method: DisarmMethod) -> Bool {
        guard case let .scannedCode(expected) = method else { return false }
        let cleaned = normalize(scanned)
        guard !cleaned.isEmpty else { return false }
        return cleaned == normalize(expected)
    }

    /// El método de desarme para un código recién escaneado, o `nil` si no vale.
    static func method(for raw: String) -> DisarmMethod? {
        let cleaned = normalize(raw)
        guard !cleaned.isEmpty else { return nil }
        return .scannedCode(value: cleaned)
    }
}
