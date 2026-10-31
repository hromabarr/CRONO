import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas del almacén contra un contenedor en memoria.
///
/// Cada prueba crea su propio contenedor, así que no comparten estado y pueden
/// ejecutarse en paralelo. No se toca el disco.
@MainActor
@Suite("Almacén de hábitos")
struct HabitStoreTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Contenedor aislado en memoria.
    func makeStore() throws -> (store: HabitStore, context: ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.crono, configurations: configuration
        )
        let context = ModelContext(container)
        return (HabitStore(context: context, calendar: calendar), context)
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 9
        return calendar.date(from: parts)!
    }

    func completionCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<HabitCompletion>())
    }

    // MARK: - Alta

    @Test("Crear un hábito lo persiste con sus valores")
    func createPersistsHabit() throws {
        let (store, _) = try makeStore()

        let habit = store.createHabit(
            name: "Meditar",
            notes: "10 minutos",
            color: .green,
            schedule: .weekdays
        )

        #expect(habit != nil)
        #expect(store.failure == nil)
        #expect(store.activeHabits().count == 1)
        #expect(habit?.color == .green)
        #expect(habit?.schedule == .weekdays)
        #expect(habit?.isActive == true)
    }

    @Test("El nombre se guarda sin espacios sobrantes")
    func nameIsTrimmed() throws {
        let (store, _) = try makeStore()

        let habit = store.createHabit(name: "  Correr \n")

        // Sin recortar, "Correr" y " Correr " serían dos hábitos distintos a
        // ojos de la base de datos e idénticos a ojos del usuario.
        #expect(habit?.name == "Correr")
    }

    @Test("Los hábitos nuevos se colocan al final")
    func newHabitsGoLast() throws {
        let (store, _) = try makeStore()

        store.createHabit(name: "Primero")
        store.createHabit(name: "Segundo")
        store.createHabit(name: "Tercero")

        #expect(store.activeHabits().map(\.name) == ["Primero", "Segundo", "Tercero"])
        #expect(store.activeHabits().map(\.sortIndex) == [0, 1, 2])
    }

    // MARK: - Compleciones

    @Test("Marcar y desmarcar no deja registros duplicados")
    func toggleIsIdempotent() throws {
        let (store, context) = try makeStore()
        let habit = try #require(store.createHabit(name: "Leer"))
        let today = habit.createdDayKey

        store.toggleCompletion(for: habit, on: today, today: today)
        #expect(habit.isCompleted(on: today))
        #expect(try completionCount(in: context) == 1)

        store.toggleCompletion(for: habit, on: today, today: today)
        #expect(habit.isCompleted(on: today) == false)
        // Desmarcar borra la fila; no deja una fila con valor "false".
        #expect(try completionCount(in: context) == 0)

        // Volver a marcar tampoco acumula.
        store.toggleCompletion(for: habit, on: today, today: today)
        store.toggleCompletion(for: habit, on: today, today: today)
        store.toggleCompletion(for: habit, on: today, today: today)
        #expect(try completionCount(in: context) == 1)
    }

    @Test("No se puede marcar un día futuro")
    func futureDayIsRejected() throws {
        let (store, context) = try makeStore()
        let habit = try #require(store.createHabit(name: "Nadar"))
        let today = habit.createdDayKey
        let tomorrow = try #require(calendar.dayKey(today, offsetByDays: 1))

        store.toggleCompletion(for: habit, on: tomorrow, today: today)

        #expect(habit.isCompleted(on: tomorrow) == false)
        #expect(try completionCount(in: context) == 0)
        // El rechazo se explica, no se ignora en silencio.
        #expect(store.failure != nil)
        #expect(store.failure?.message.contains("aún no ha llegado") == true)
    }

    @Test("No se puede marcar un día anterior a la creación")
    func dayBeforeCreationIsRejected() throws {
        let (store, context) = try makeStore()
        let habit = try #require(store.createHabit(name: "Estirar"))
        let created = habit.createdDayKey
        let dayBefore = try #require(calendar.dayKey(created, offsetByDays: -1))

        store.toggleCompletion(for: habit, on: dayBefore, today: created)

        #expect(try completionCount(in: context) == 0)
        #expect(store.failure != nil)
    }

    @Test("Se puede rellenar un día pasado")
    func pastDayIsAllowed() throws {
        let (store, context) = try makeStore()

        // Hábito creado hace una semana, para que haya pasado que rellenar.
        let habit = Habit(name: "Diario", createdAt: date(2026, 7, 20))
        context.insert(habit)
        try context.save()

        let today = calendar.dayKey(from: date(2026, 7, 27))
        let pastDay = calendar.dayKey(from: date(2026, 7, 23))

        store.toggleCompletion(for: habit, on: pastDay, today: today)

        #expect(habit.isCompleted(on: pastDay))
        #expect(store.failure == nil)
    }

    // MARK: - Archivar frente a borrar

    @Test("Archivar conserva el historial")
    func archiveKeepsHistory() throws {
        let (store, context) = try makeStore()
        let habit = try #require(store.createHabit(name: "Guitarra"))
        let today = habit.createdDayKey

        store.toggleCompletion(for: habit, on: today, today: today)
        #expect(try completionCount(in: context) == 1)

        store.archive(habit, on: date(2026, 7, 27))

        #expect(habit.isActive == false)
        #expect(store.activeHabits().isEmpty)
        #expect(store.archivedHabits().count == 1)
        // Lo importante: el registro sobrevive, así que la mejor racha
        // conseguida sigue siendo consultable.
        #expect(try completionCount(in: context) == 1)
    }

    @Test("Reactivar devuelve el hábito a la lista")
    func unarchiveRestoresHabit() throws {
        let (store, _) = try makeStore()
        let habit = try #require(store.createHabit(name: "Pintar"))

        store.archive(habit, on: date(2026, 7, 27))
        #expect(store.activeHabits().isEmpty)

        store.unarchive(habit)
        #expect(store.activeHabits().count == 1)
        #expect(habit.isActive)
    }

    @Test("Borrar arrastra los registros en cascada")
    func deleteCascades() throws {
        let (store, context) = try makeStore()

        // Creado hace una semana, para que haya varios días marcables de
        // verdad y la cascada se pruebe con más de una fila.
        let habit = Habit(name: "Yoga", createdAt: date(2026, 7, 20))
        context.insert(habit)
        try context.save()

        let today = calendar.dayKey(from: date(2026, 7, 27))
        let yesterday = calendar.dayKey(from: date(2026, 7, 26))

        store.toggleCompletion(for: habit, on: today, today: today)
        store.toggleCompletion(for: habit, on: yesterday, today: today)
        #expect(try completionCount(in: context) == 2)

        store.delete(habit)

        #expect(store.activeHabits().isEmpty)
        #expect(try completionCount(in: context) == 0)
    }

    // MARK: - Edición y orden

    @Test("Editar cambia todos los campos a la vez")
    func updateChangesFields() throws {
        let (store, _) = try makeStore()
        let habit = try #require(
            store.createHabit(name: "Antiguo", color: .red, schedule: .everyDay)
        )

        store.update(
            habit,
            name: "Nuevo",
            notes: "Con nota",
            color: .purple,
            schedule: [.tuesday, .thursday]
        )

        #expect(habit.name == "Nuevo")
        #expect(habit.notes == "Con nota")
        #expect(habit.color == .purple)
        #expect(habit.schedule == [.tuesday, .thursday])
        #expect(habit.isDaily == false)
        #expect(store.failure == nil)
    }

    @Test("Reordenar normaliza los índices sin huecos")
    func moveNormalisesIndices() throws {
        let (store, _) = try makeStore()
        store.createHabit(name: "A")
        store.createHabit(name: "B")
        store.createHabit(name: "C")

        let habits = store.activeHabits()
        // Mover "C" al principio.
        store.move(habits, from: IndexSet(integer: 2), to: 0)

        let reordered = store.activeHabits()
        #expect(reordered.map(\.name) == ["C", "A", "B"])
        // Los índices quedan 0,1,2: sin huecos que acaben colisionando.
        #expect(reordered.map(\.sortIndex) == [0, 1, 2])
    }

    @Test("Un color desconocido cae en el color por defecto")
    func unknownColorFallsBack() throws {
        let (store, context) = try makeStore()
        let habit = try #require(store.createHabit(name: "Raro", color: .teal))

        // Simula un dato escrito por una versión distinta de la app.
        habit.colorRaw = "chartreuse"
        try context.save()

        // Prefiere degradarse a azul antes que fallar al dibujar la fila.
        #expect(habit.color == HabitColor.default)
    }

    // MARK: - Cantidad

    @Test("Sumar en un hábito con cantidad solo lo cumple al llegar al objetivo")
    func incrementReachesGoal() throws {
        let (store, context) = try makeStore()
        let habit = try #require(store.createHabit(name: "Agua", targetCount: 3, unit: "vasos"))
        let day = habit.createdDayKey

        store.advance(habit, on: day, today: day)
        store.advance(habit, on: day, today: day)
        #expect(habit.count(on: day) == 2)
        #expect(!habit.isCompleted(on: day))
        #expect(habit.progressText(on: day) == "2 de 3 vasos")
        // Una sola fila por día aunque se sume varias veces.
        #expect(try completionCount(in: context) == 1)

        store.advance(habit, on: day, today: day)
        #expect(habit.isCompleted(on: day))
        #expect(habit.completedDayKeys == [day])

        // Pasarse del objetivo vale: nueve vasos de ocho siguen siendo un día
        // cumplido.
        store.advance(habit, on: day, today: day)
        #expect(habit.count(on: day) == 4)
        #expect(habit.isCompleted(on: day))
    }

    @Test("Restar hasta cero borra el registro")
    func decrementToZeroDeletes() throws {
        let (store, context) = try makeStore()
        let habit = try #require(store.createHabit(name: "Páginas", targetCount: 10))
        let day = habit.createdDayKey

        store.increment(habit, on: day, today: day)
        store.increment(habit, on: day, today: day)
        store.decrement(habit, on: day, today: day)
        #expect(habit.count(on: day) == 1)

        store.decrement(habit, on: day, today: day)
        #expect(habit.count(on: day) == 0)
        #expect(try completionCount(in: context) == 0)

        // Restar sin nada apuntado no hace nada ni falla.
        store.decrement(habit, on: day, today: day)
        #expect(store.failure == nil)
    }

    @Test("Marcar un hábito con cantidad lo lleva al objetivo, y desmarcar a cero")
    func toggleQuantityHabit() throws {
        let (store, _) = try makeStore()
        let habit = try #require(store.createHabit(name: "Agua", targetCount: 8))
        let day = habit.createdDayKey

        store.increment(habit, on: day, today: day)
        store.toggleCompletion(for: habit, on: day, today: day)
        #expect(habit.count(on: day) == 8)
        #expect(habit.isCompleted(on: day))

        store.toggleCompletion(for: habit, on: day, today: day)
        #expect(habit.count(on: day) == 0)
    }

    @Test("Subir el objetivo vuelve a evaluar los días ya apuntados")
    func raisingGoalReevaluates() throws {
        let (store, _) = try makeStore()
        let habit = try #require(store.createHabit(name: "Leer"))
        let day = habit.createdDayKey
        store.toggleCompletion(for: habit, on: day, today: day)
        #expect(habit.isCompleted(on: day))

        store.update(
            habit,
            name: habit.name,
            notes: habit.notes,
            color: habit.color,
            schedule: habit.schedule,
            targetCount: 5,
            unit: "páginas"
        )

        #expect(habit.hasQuantityGoal)
        #expect(!habit.isCompleted(on: day))
        #expect(habit.count(on: day) == 1)
    }

    @Test("El objetivo se queda entre 1 y el tope")
    func goalIsClamped() throws {
        let (store, _) = try makeStore()
        let low = try #require(store.createHabit(name: "Cero", targetCount: 0))
        let high = try #require(store.createHabit(name: "Mucho", targetCount: 5000))

        #expect(low.targetCount == 1)
        #expect(high.targetCount == Habit.maxTarget)
    }

    @Test("No se suma en días futuros")
    func noIncrementInFuture() throws {
        let (store, _) = try makeStore()
        let habit = try #require(store.createHabit(name: "Agua", targetCount: 8))
        let today = habit.createdDayKey
        let tomorrow = try #require(calendar.dayKey(today, offsetByDays: 1))

        store.increment(habit, on: tomorrow, today: today)

        #expect(habit.count(on: tomorrow) == 0)
        #expect(store.failure != nil)
    }
}
