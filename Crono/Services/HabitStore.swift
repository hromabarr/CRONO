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
        schedule: WeekdaySet = .everyDay,
        routine: HabitRoutine = .anytime,
        targetCount: Int = 1,
        unit: String = ""
    ) -> Habit? {
        let habit = Habit(
            name: name.trimmedForStorage,
            notes: notes.trimmedForStorage,
            color: color,
            schedule: schedule,
            sortIndex: nextSortIndex(),
            routine: routine,
            targetCount: targetCount,
            unit: unit.trimmedForStorage
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
        schedule: WeekdaySet,
        routine: HabitRoutine? = nil,
        targetCount: Int? = nil,
        unit: String? = nil
    ) {
        habit.name = name.trimmedForStorage
        habit.notes = notes.trimmedForStorage
        habit.color = color
        habit.schedule = schedule
        if let routine { habit.routine = routine }
        // Cambiar el objetivo no reescribe el pasado: los días ya registrados
        // se vuelven a evaluar contra el objetivo nuevo, igual que una racha se
        // recalcula al cambiar los días programados.
        if let targetCount { habit.targetCount = Habit.clampedTarget(targetCount) }
        if let unit { habit.unit = unit.trimmedForStorage }

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
        let reordered = habits.reordered(from: source, to: destination)

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
    ///
    /// En un hábito con cantidad, marcar es llegar al objetivo de golpe y
    /// desmarcar es volver a cero: es lo que piden la rutina y el editor de
    /// días, que tratan cada hábito como un paso hecho o por hacer.
    func toggleCompletion(for habit: Habit, on dayKey: DayKey, today: DayKey? = nil) {
        let existing = habit.completion(on: dayKey)
        let completing = !habit.isCompleted(on: dayKey)
        guard canRecord(habit, on: dayKey, today: today, adding: completing, action: "marcar el hábito") else {
            return
        }

        if !completing, let existing {
            context.delete(existing)
        } else if let existing {
            existing.count = habit.targetCount
        } else {
            insertCompletion(for: habit, on: dayKey, count: habit.targetCount)
        }

        if !save(action: "guardar el registro") { context.rollback() }
    }

    /// Lo que hace tocar un hábito: sumar uno si se mide en cantidad, marcar o
    /// desmarcar si es de sí o no.
    func advance(_ habit: Habit, on dayKey: DayKey, today: DayKey? = nil) {
        if habit.hasQuantityGoal {
            increment(habit, on: dayKey, today: today)
        } else {
            toggleCompletion(for: habit, on: dayKey, today: today)
        }
    }

    /// Suma uno a lo hecho ese día. Se puede pasar del objetivo, hasta
    /// `Habit.maxDailyCount`.
    func increment(_ habit: Habit, on dayKey: DayKey, today: DayKey? = nil) {
        guard canRecord(habit, on: dayKey, today: today, adding: true, action: "sumar al hábito") else {
            return
        }

        if let existing = habit.completion(on: dayKey) {
            guard existing.count < Habit.maxDailyCount else { return }
            existing.count += 1
        } else {
            insertCompletion(for: habit, on: dayKey, count: 1)
        }

        if !save(action: "guardar el registro") { context.rollback() }
    }

    /// Resta uno a lo hecho ese día. Al llegar a cero se borra el registro.
    func decrement(_ habit: Habit, on dayKey: DayKey, today: DayKey? = nil) {
        guard let existing = habit.completion(on: dayKey) else { return }
        guard canRecord(habit, on: dayKey, today: today, adding: false, action: "restar al hábito") else {
            return
        }

        if existing.count <= 1 {
            context.delete(existing)
        } else {
            existing.count -= 1
        }

        if !save(action: "guardar el registro") { context.rollback() }
    }

    /// Las reglas de qué días se pueden tocar, compartidas por marcar, sumar y
    /// restar.
    ///
    /// `adding` distingue apuntar de quitar: quitar un registro de un día en que
    /// el hábito ya estaba archivado se permite, porque corrige un error; añadir
    /// uno, no.
    private func canRecord(
        _ habit: Habit,
        on dayKey: DayKey,
        today: DayKey?,
        adding: Bool,
        action: String
    ) -> Bool {
        let referenceToday = today ?? Date.now.dayKey
        guard calendar.date(fromDayKey: dayKey) != nil else {
            failure = StoreFailure(action: action, reason: "La fecha no es válida.")
            return false
        }

        // Marcar el futuro no significa nada: un hábito no puede cumplirse antes
        // de que llegue su día.
        guard dayKey <= referenceToday else {
            failure = StoreFailure(action: action, reason: "Ese día aún no ha llegado.")
            return false
        }

        guard dayKey >= habit.createdDayKey else {
            failure = StoreFailure(action: action, reason: "Es anterior a la creación del hábito.")
            return false
        }

        if adding, let archivedAt = habit.archivedAt, dayKey > calendar.dayKey(from: archivedAt) {
            failure = StoreFailure(action: action, reason: "El hábito ya estaba archivado ese día.")
            return false
        }

        return true
    }

    private func insertCompletion(for habit: Habit, on dayKey: DayKey, count: Int) {
        let completion = HabitCompletion(dayKey: dayKey, count: count)
        // Insertar antes de enlazar: así SwiftData ya gestiona el objeto
        // cuando se establece la relación inversa.
        context.insert(completion)
        completion.habit = habit
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
        failure = nil
        // Sin cambios pendientes no se toca el disco. Editar un hábito sin
        // modificar nada, o reordenar dejándolo en el mismo sitio, no debería
        // provocar escritura alguna ni, sobre todo, poder fallar.
        guard context.hasChanges else { return true }

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
