import Foundation
import SwiftData

/// Fallo de una operación de escritura, listo para mostrarse.
///
/// Existe para que los errores no se traguen con `try?`. Un `save` que falla
/// —disco lleno, base corrupta— tiene que llegar al usuario: si desaparece en
/// silencio, la app parece haber guardado algo que no guardó.
struct StoreFailure: Identifiable, Equatable {
    let id = UUID()
    /// La acción en infinitivo, para componer "No se pudo <acción>".
    let action: String
    let reason: String

    var message: String { "No se pudo \(action). \(reason)" }

    static func == (lhs: StoreFailure, rhs: StoreFailure) -> Bool { lhs.id == rhs.id }
}

/// Único punto de escritura sobre los datos.
///
/// Las vistas leen con `@Query` —la fuente reactiva de SwiftData— pero nunca
/// escriben en el `ModelContext` directamente. Concentrar las mutaciones aquí
/// mantiene en un solo sitio las reglas que no son evidentes: la unicidad de
/// (hábito, día), el orden de la lista y el rechazo de fechas futuras.
///
/// Está marcado `@MainActor` porque `ModelContext` no es `Sendable`: el contexto
/// de la vista pertenece al hilo principal y compartirlo entre tareas sería un
/// error de concurrencia, no una optimización.
@MainActor
@Observable
final class HabitStore {
    private let context: ModelContext
    private let calendar: Calendar

    /// Último fallo sin descartar. La UI lo presenta y lo pone a `nil`.
    var failure: StoreFailure?

    init(context: ModelContext, calendar: Calendar = AppCalendar.current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - Altas y bajas

    /// Crea un hábito y lo coloca al final de la lista.
    @discardableResult
    func createHabit(
        name: String,
        notes: String = "",
        color: HabitColor = .default,
        schedule: WeekdaySet = .everyDay
    ) -> Habit? {
        let habit = Habit(
            name: name.trimmedForStorage,
            notes: notes.trimmedForStorage,
            color: color,
            schedule: schedule,
            sortIndex: nextSortIndex()
        )
        context.insert(habit)

        guard save(action: "crear el hábito") else {
            // El insert queda deshecho para que la lista en pantalla no muestre
            // un hábito que no llegó a persistirse.
            context.rollback()
            return nil
        }
        return habit
    }

    func update(
        _ habit: Habit,
        name: String,
        notes: String,
        color: HabitColor,
        schedule: WeekdaySet
    ) {
        habit.name = name.trimmedForStorage
        habit.notes = notes.trimmedForStorage
        habit.color = color
        habit.schedule = schedule

        if !save(action: "guardar los cambios") { context.rollback() }
    }

    /// Da de baja el hábito conservando su historial.
    func archive(_ habit: Habit, on date: Date = .now) {
        habit.archivedAt = date
        if !save(action: "archivar el hábito") { context.rollback() }
    }

    func unarchive(_ habit: Habit) {
        habit.archivedAt = nil
        habit.sortIndex = nextSortIndex()
        if !save(action: "reactivar el hábito") { context.rollback() }
    }

    /// Borra el hábito y, en cascada, todos sus registros. Es irreversible.
    func delete(_ habit: Habit) {
        context.delete(habit)
        if !save(action: "eliminar el hábito") { context.rollback() }
    }

    // MARK: - Orden

    /// Reordena la lista de activos según el resultado de un arrastre.
    ///
    /// Recibe la lista tal y como la ve el usuario, porque `onMove` da índices
    /// relativos a ese orden y no al valor de `sortIndex`, que puede tener
    /// huecos tras archivar o borrar.
    func move(_ habits: [Habit], from source: IndexSet, to destination: Int) {
        var reordered = habits

        // El `move(fromOffsets:toOffset:)` que se usaría aquí lo aporta SwiftUI,
        // no la biblioteca estándar. Se implementa a mano en lugar de importar
        // SwiftUI: un servicio de datos no debe depender de un framework de
        // interfaz para reordenar un array.
        let moving = source.map { habits[$0] }
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        // `destination` es un índice sobre el array original, así que hay que
        // descontar los elementos extraídos que estaban antes de ese punto.
        let removedBefore = source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: destination - removedBefore)

        // Se reescriben todos los índices: normalizarlos a 0..<n evita que los
        // huecos se acumulen y acaben colisionando.
        for (index, habit) in reordered.enumerated() {
            habit.sortIndex = index
        }

        if !save(action: "reordenar los hábitos") { context.rollback() }
    }

    // MARK: - Compleciones

    /// Marca o desmarca un hábito en un día.
    ///
    /// Aquí vive la unicidad de (hábito, día): `#Unique` no puede expresarse
    /// sobre una relación, así que se garantiza buscando antes de insertar.
    func toggleCompletion(for habit: Habit, on dayKey: DayKey, today: DayKey? = nil) {
        let referenceToday = today ?? Date.now.dayKey

        // Marcar el futuro no significa nada: un hábito no puede cumplirse antes
        // de que llegue su día.
        guard dayKey <= referenceToday else {
            failure = StoreFailure(
                action: "marcar el hábito",
                reason: "Ese día aún no ha llegado."
            )
            return
        }

        guard dayKey >= habit.createdDayKey else {
            failure = StoreFailure(
                action: "marcar el hábito",
                reason: "Es anterior a la creación del hábito."
            )
            return
        }

        if let existing = habit.completion(on: dayKey) {
            context.delete(existing)
        } else {
            let completion = HabitCompletion(dayKey: dayKey)
            // Insertar antes de enlazar: así SwiftData ya gestiona el objeto
            // cuando se establece la relación inversa.
            context.insert(completion)
            completion.habit = habit
        }

        if !save(action: "guardar el registro") { context.rollback() }
    }

    // MARK: - Consultas

    /// Hábitos activos en el orden elegido por el usuario.
    ///
    /// Las vistas normalmente usan `@Query`; esto está para los ViewModels y las
    /// pruebas, que necesitan leer sin depender de una vista.
    func activeHabits() -> [Habit] {
        var descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.completions]

        do {
            return try context.fetch(descriptor)
        } catch {
            failure = StoreFailure(
                action: "cargar los hábitos",
                reason: error.localizedDescription
            )
            return []
        }
    }

    func archivedHabits() -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            failure = StoreFailure(
                action: "cargar los hábitos archivados",
                reason: error.localizedDescription
            )
            return []
        }
    }

    // MARK: - Internos

    /// Índice siguiente al mayor en uso, para colocar lo nuevo al final.
    private func nextSortIndex() -> Int {
        var descriptor = FetchDescriptor<Habit>(
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let highest = (try? context.fetch(descriptor))?.first?.sortIndex ?? -1
        return highest + 1
    }

    /// Persiste y traduce el fallo a algo mostrable. Devuelve `false` si falló.
    private func save(action: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            failure = StoreFailure(action: action, reason: error.localizedDescription)
            return false
        }
    }
}

// MARK: - Auxiliares

private extension String {
    /// Recorta espacios y saltos antes de guardar, para que " Correr " y
    /// "Correr" no acaben siendo dos hábitos distintos a ojos del usuario.
    var trimmedForStorage: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
