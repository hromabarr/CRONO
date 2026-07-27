import Foundation
import SwiftData

/// Marca de que un hábito se completó en un día concreto.
///
/// No existe un campo `isCompleted`: la existencia de la fila *es* la compleción.
/// Desmarcar borra la fila. Esto evita el estado ambiguo de tener filas con
/// `false` mezcladas con la ausencia de fila, que son lo mismo pero se consultan
/// de forma distinta.
@Model
final class HabitCompletion {
    /// La vista de historial pide "todas las compleciones del mes visible", es
    /// decir un rango sobre `dayKey`. El índice evita recorrer la tabla completa
    /// cuando el historial acumula miles de registros.
    #Index<HabitCompletion>([\.dayKey])

    @Attribute(.unique) var uuid: UUID

    /// Día de calendario al que corresponde, en formato `yyyyMMdd`.
    /// Indexado porque la vista de historial consulta por rangos de mes.
    var dayKey: DayKey

    /// Instante real en que el usuario marcó el hábito.
    ///
    /// No se usa para agrupar por día —para eso está `dayKey`—, pero conserva la
    /// hora, que es la base de cualquier estadística futura del tipo "suelo
    /// cumplir por la mañana".
    var completedAt: Date

    /// Hábito al que pertenece. Es opcional porque SwiftData exige que el lado
    /// inverso de una relación lo sea; en la práctica nunca es `nil`, ya que el
    /// borrado del hábito arrastra sus registros en cascada.
    var habit: Habit?

    init(
        uuid: UUID = UUID(),
        dayKey: DayKey,
        completedAt: Date = .now,
        habit: Habit? = nil
    ) {
        self.uuid = uuid
        self.dayKey = dayKey
        self.completedAt = completedAt
        self.habit = habit
    }
}
