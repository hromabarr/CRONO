import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas del almacén de tareas contra un contenedor en memoria.
@MainActor
@Suite("Almacén de tareas")
struct ReminderStoreTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func makeStore() throws -> (store: ReminderStore, context: ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Habit.self, HabitCompletion.self, ReminderList.self, Reminder.self, AlarmItem.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        return (ReminderStore(context: context), context)
    }

    // MARK: - Listas

    @Test("La lista por defecto se crea una sola vez")
    func defaultListIsCreatedOnce() throws {
        let (store, _) = try makeStore()

        let first = try #require(store.ensureDefaultList())
        #expect(first.name == ReminderStore.defaultListName)
        #expect(store.allLists().count == 1)

        // Segunda llamada: devuelve la existente, no crea otra. Sin esto, cada
        // arranque de la app añadiría una lista vacía más.
        let second = store.ensureDefaultList()
        #expect(second?.uuid == first.uuid)
        #expect(store.allLists().count == 1)
    }

    @Test("Borrar una lista arrastra sus tareas")
    func deletingListCascades() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.createList(name: "Casa"))

        store.createReminder(title: "Fregar", in: list)
        store.createReminder(title: "Barrer", in: list)
        #expect(try context.fetchCount(FetchDescriptor<Reminder>()) == 2)

        store.delete(list)

        #expect(store.allLists().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Reminder>()) == 0)
    }

    // MARK: - Vencimiento

    @Test("Una hora sin día se descarta")
    func timeWithoutDateIsDropped() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        // Una hora sin fecha no significa nada y la interfaz no sabría
        // representarla: mejor no guardar el estado imposible.
        let reminder = try #require(
            store.createReminder(title: "Llamar", in: list, dueMinuteOfDay: 600)
        )

        #expect(reminder.dueDayKey == nil)
        #expect(reminder.dueMinuteOfDay == nil)
        #expect(reminder.hasDueTime == false)
    }

    @Test("Con día y hora sí hay aviso posible")
    func dateAndTimeIsSchedulable() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let reminder = try #require(
            store.createReminder(
                title: "Dentista",
                in: list,
                dueDayKey: 20_260_729,
                dueMinuteOfDay: 10 * 60 + 30
            )
        )

        #expect(reminder.hasDueDate)
        #expect(reminder.hasDueTime)

        let due = try #require(reminder.dueDate(calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        #expect(parts.year == 2026)
        #expect(parts.month == 7)
        #expect(parts.day == 29)
        #expect(parts.hour == 10)
        #expect(parts.minute == 30)
    }

    @Test("Quitar la fecha quita también la hora")
    func clearingDateClearsTime() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let reminder = try #require(
            store.createReminder(
                title: "Revisar",
                in: list,
                dueDayKey: 20_260_729,
                dueMinuteOfDay: 540
            )
        )

        store.update(
            reminder,
            title: reminder.title,
            notes: "",
            dueDayKey: nil,
            dueMinuteOfDay: 540,
            priority: .none,
            isFlagged: false,
            recurrence: nil,
            list: nil
        )

        #expect(reminder.dueDayKey == nil)
        // Sin la limpieza quedaría una hora huérfana que nada sabría mostrar.
        #expect(reminder.dueMinuteOfDay == nil)
    }

    @Test("Una tarea está atrasada si su día pasó y sigue pendiente")
    func overdueDetection() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let today: DayKey = 20_260_727

        let past = try #require(store.createReminder(title: "Ayer", in: list, dueDayKey: 20_260_726))
        let laterToday = try #require(
            store.createReminder(title: "Luego", in: list, dueDayKey: today, dueMinuteOfDay: 18 * 60)
        )
        let earlierToday = try #require(
            store.createReminder(title: "Antes", in: list, dueDayKey: today, dueMinuteOfDay: 8 * 60)
        )
        let undated = try #require(store.createReminder(title: "Algún día", in: list))

        let noon = 12 * 60
        #expect(past.isOverdue(today: today, nowMinuteOfDay: noon))
        #expect(earlierToday.isOverdue(today: today, nowMinuteOfDay: noon))
        #expect(laterToday.isOverdue(today: today, nowMinuteOfDay: noon) == false)
        // Sin fecha no se puede llegar tarde.
        #expect(undated.isOverdue(today: today, nowMinuteOfDay: noon) == false)

        // Y una vez hecha, deja de estar atrasada.
        store.toggleCompletion(for: past)
        #expect(past.isOverdue(today: today, nowMinuteOfDay: noon) == false)
    }

    // MARK: - Completar

    @Test("Completar una tarea madre completa sus subtareas")
    func completingParentCompletesSubtasks() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let parent = try #require(store.createReminder(title: "Mudanza", in: list))

        let a = try #require(store.createReminder(title: "Cajas", in: list, parent: parent))
        let b = try #require(store.createReminder(title: "Furgoneta", in: list, parent: parent))

        #expect(parent.subtaskProgress == Reminder.SubtaskProgress(completed: 0, total: 2))

        store.toggleCompletion(for: parent)

        // Dejar subtareas pendientes bajo una tarea hecha sería un estado que el
        // usuario no puede interpretar.
        #expect(parent.isCompleted)
        #expect(a.isCompleted)
        #expect(b.isCompleted)
        #expect(parent.subtaskProgress == Reminder.SubtaskProgress(completed: 2, total: 2))
    }

    @Test("Desmarcar la madre no desmarca las subtareas")
    func uncompletingParentLeavesSubtasks() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let parent = try #require(store.createReminder(title: "Informe", in: list))
        let subtask = try #require(store.createReminder(title: "Gráficas", in: list, parent: parent))

        store.toggleCompletion(for: parent)
        store.toggleCompletion(for: parent)

        #expect(parent.isCompleted == false)
        #expect(parent.completedAt == nil)
        // Si la subtarea estaba hecha, lo estaba: reabrir la madre no deshace
        // trabajo que sí se hizo.
        #expect(subtask.isCompleted)
    }

    @Test("Borrar las completadas deja solo las pendientes")
    func clearCompletedKeepsPending() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let done = try #require(store.createReminder(title: "Hecha", in: list))
        store.createReminder(title: "Pendiente", in: list)
        store.toggleCompletion(for: done)

        store.clearCompleted(in: list)

        let remaining = try context.fetch(FetchDescriptor<Reminder>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Pendiente")
    }

    // MARK: - Orden

    @Test("Las tareas nuevas se colocan al final de su lista")
    func newRemindersGoLast() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let a = try #require(store.createReminder(title: "A", in: list))
        let b = try #require(store.createReminder(title: "B", in: list))
        let c = try #require(store.createReminder(title: "C", in: list))

        let indices: [Int] = [a.sortIndex, b.sortIndex, c.sortIndex]
        let expected: [Int] = [0, 1, 2]
        #expect(indices == expected)
    }

    @Test("Reordenar normaliza los índices sin huecos")
    func moveNormalisesIndices() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        store.createReminder(title: "A", in: list)
        store.createReminder(title: "B", in: list)
        store.createReminder(title: "C", in: list)

        let ordered = list.reminders.sorted { $0.sortIndex < $1.sortIndex }
        store.moveReminders(ordered, from: IndexSet(integer: 2), to: 0)

        let after = list.reminders.sorted { $0.sortIndex < $1.sortIndex }
        let titles: [String] = after.map { $0.title }
        let expectedTitles: [String] = ["C", "A", "B"]
        #expect(titles == expectedTitles)

        let indices: [Int] = after.map { $0.sortIndex }
        let expectedIndices: [Int] = [0, 1, 2]
        #expect(indices == expectedIndices)
    }

    // MARK: - Filtros

    @Test("Las tareas sin fecha se ordenan al final")
    func undatedRemindersSortLast() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        store.createReminder(title: "Sin fecha", in: list)
        store.createReminder(title: "Pasado mañana", in: list, dueDayKey: 20_260_729)
        store.createReminder(title: "Mañana", in: list, dueDayKey: 20_260_728)

        let sorted = store.pendingReminders().byDueDateUndatedLast

        // SwiftData ordena `nil` primero; una tarea sin vencimiento no debe
        // encabezar una lista ordenada por urgencia.
        let titles: [String] = sorted.map { $0.title }
        let expectedTitles: [String] = ["Mañana", "Pasado mañana", "Sin fecha"]
        #expect(titles == expectedTitles)
    }

    @Test("Las subtareas no cuentan como tareas de nivel superior")
    func subtasksAreNotTopLevel() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let parent = try #require(store.createReminder(title: "Madre", in: list))
        store.createReminder(title: "Hija", in: list, parent: parent)

        #expect(store.pendingReminders().count == 2)
        #expect(store.pendingReminders().topLevel.count == 1)
        // El contador de la lista cuenta lo que se ve, no lo que hay.
        #expect(list.pendingCount == 1)
    }

    // MARK: - Repetición

    @Test("La regla de repetición sobrevive al viaje por la base de datos")
    func recurrenceRoundTrips() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let weekly = RecurrenceRule.weekly([.monday, .wednesday, .friday])
        let reminder = try #require(
            store.createReminder(title: "Regar", in: list, recurrence: weekly)
        )

        // Se compara por `rawValue`, que es `String`, y no por valor de enum.
        //
        // `RecurrenceRule?` contra un `RecurrenceRule` —o peor, contra un
        // miembro implícito como `.daily`— dentro de la expansión de `#expect`
        // dejaba al compilador sin poder elegir sobrecarga de `==`. La macro
        // envuelve los operandos en capturas genéricas, y ahí el tipo del lado
        // derecho queda menos determinado que en una comparación normal.
        //
        // Comparar cadenas no tiene esa duda y además comprueba exactamente lo
        // que interesa: que el viaje a la base de datos y de vuelta no pierde la
        // máscara de días.
        #expect(reminder.recurrence?.rawValue == weekly.rawValue)
        // La máscara viaja dentro de la cadena: `weekly:42`.
        #expect(reminder.recurrenceRaw == "weekly:42")

        #expect(RecurrenceRule(rawValue: "daily")?.rawValue == "daily")
        #expect(RecurrenceRule(rawValue: "monthly")?.rawValue == "monthly")
        #expect(RecurrenceRule(rawValue: "yearly")?.rawValue == "yearly")
        #expect(RecurrenceRule(rawValue: "basura") == nil)
        #expect(RecurrenceRule(rawValue: "weekly:sinnúmero") == nil)
    }
}
