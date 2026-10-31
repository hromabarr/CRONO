import Foundation

/// La cuenta que hay que resolver para desarmar.
///
/// Una multiplicación de una cifra por dos y una suma: no se hace de memoria
/// sin pensar, pero tampoco hace falta papel. El objetivo es estar despierto,
/// no aprobar un examen a las siete de la mañana.
struct ArithmeticChallenge: Equatable, Sendable {
    let factor: Int
    let multiplier: Int
    let addend: Int

    var answer: Int { factor * multiplier + addend }

    var question: String { "\(factor) × \(multiplier) + \(addend)" }

    /// Si lo escrito es la respuesta. Solo se perdonan los espacios: un teclado
    /// numérico no deja escribir otra cosa.
    func accepts(_ input: String) -> Bool {
        Int(input.trimmingCharacters(in: .whitespacesAndNewlines)) == answer
    }

    static func make<Generator: RandomNumberGenerator>(using generator: inout Generator) -> ArithmeticChallenge {
        ArithmeticChallenge(
            factor: Int.random(in: 3...9, using: &generator),
            multiplier: Int.random(in: 12...19, using: &generator),
            addend: Int.random(in: 11...99, using: &generator)
        )
    }

    static func make() -> ArithmeticChallenge {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }
}
