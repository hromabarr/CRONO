import Foundation

extension Array {
    /// Aplica un arrastre de `onMove` y devuelve el array reordenado.
    ///
    /// Existe por dos razones. La primera: el `move(fromOffsets:toOffset:)` que
    /// se usaría aquí lo aporta SwiftUI, y los servicios de datos no deben
    /// depender de un framework de interfaz para reordenar un array. La segunda:
    /// estaba escrito dos veces —en `HabitStore` y en `ReminderStore`— y es un
    /// algoritmo con riesgo de desfase por uno; dos copias acaban divergiendo.
    ///
    /// `destination` es un índice sobre el array **original**, tal como lo
    /// entrega `onMove`, así que hay que descontar los elementos extraídos que
    /// estaban antes de ese punto.
    func reordered(from source: IndexSet, to destination: Int) -> [Element] {
        var result = self
        let moving = source.map { self[$0] }

        for index in source.sorted(by: >) {
            result.remove(at: index)
        }

        let removedBefore = source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: destination - removedBefore)

        return result
    }
}
