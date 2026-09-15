import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas de lo que ocurre al completar una tarea recurrente, y de qué tareas
/// merecen un aviso.
@MainActor
@Suite("Tareas recurrentes y avisos")
struct ReminderRecurrenceTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func makeStore() throws -> (store: ReminderStore, context: ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.crono, configurations: configuration
        )
        let context = ModelContext(container)
        return (ReminderStore(context: context, calendar: calendar), context)
    }

    func allReminders(_ context: ModelContext) throws -> [Reminder] {
        try context.fetch(FetchDescriptor<Reminder>())
    }

    // MARK: - Nace la siguiente

    @Test("Completar una tarea recurrente crea la siguiente")
    func completingCreatesSuccessor() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let task = try #require(
            store.createReminder(
                title: "Regar las plantas",
                in: list,
                dueDayKey: 20_260_914,
                dueMinuteOfDay: 9 * 60,
                recurrence: .daily
            )
        )

        store.toggleCompletion(for: task)

        let all = try allReminders(context)
        #expect(all.count == 2)

        // Los resultados de `first(where:)` y `count` se atan fuera de las
        // macros: ambos son `rethrows`, y dentro de la expansión de `#expect` o
        // `#require` el compilador pierde la inferencia de que el cierre no
        // lanza y exige un `try`.

        // La completada se queda completada: mover su fecha en lugar de crear
        // una nueva borraría cualquier rastro de que se cumplió.
        #expect(task.isCompleted)

        let pending = all.filter { !$0.isCompleted }
        let successor = try #require(pending.first)
        #expect(successor.title == "Regar las plantas")
        #expect(successor.dueDayKey == 20_260_915)
        // La hora y las marcas se heredan.
        #expect(successor.dueMinuteOfDay == 9 * 60)
        #expect(successor.recurrence?.rawValue == "daily")
        #expect(successor.list?.uuid == list.uuid)
    }

    @Test("La siguiente hereda prioridad y bandera")
    func successorInheritsMarkers() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let task = try #require(
            store.createReminder(
                title: "Informe semanal",
                in: list,
                dueDayKey: 20_260_914,
                dueMinuteOfDay: 10 * 60,
                priority: .high,
                isFlagged: true,
                recurrence: .weekly([.monday])
            )
        )

        store.toggleCompletion(for: task)

        let pending = try allReminders(context).filter { !$0.isCompleted }
        let successor = try #require(pending.first)
        #expect(successor.priority == .high)
        #expect(successor.isFlagged)
        // 14/09/2026 es lunes; el siguiente lunes es el 21.
        #expect(successor.dueDayKey == 20_260_921)
    }

    @Test("Las subtareas se copian sin marcar")
    func subtasksAreCopiedUnchecked() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let task = try #require(
            store.createReminder(
                title: "Revisión del coche",
                in: list,
                dueDayKey: 20_260_914,
                dueMinuteOfDay: 8 * 60,
                recurrence: .monthly
            )
        )
        store.createReminder(title: "Aceite", in: list, parent: task)
        store.createReminder(title: "Neumáticos", in: list, parent: task)

        store.toggleCompletion(for: task)

        let topLevelPending = try allReminders(context)
            .filter { !$0.isCompleted && $0.parent == nil }
        let successor = try #require(topLevelPending.first)

        // Una lista de comprobación que reapareciera ya completada no serviría
        // de nada.
        #expect(successor.subtasks.count == 2)
        let anyCompleted = successor.subtasks.contains { $0.isCompleted }
        #expect(anyCompleted == false)

        let titles = successor.subtasks.map { $0.title }.sorted()
        let expected: [String] = ["Aceite", "Neumáticos"]
        #expect(titles == expected)

        // Y las de la tarea completada sí quedaron marcadas.
        let originalDone = task.subtasks.allSatisfy { $0.isCompleted }
        #expect(originalDone)
    }

    // MARK: - Cuándo NO nace

    @Test("Una tarea sin repetición no crea ninguna siguiente")
    func nonRecurringCreatesNothing() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let task = try #require(
            store.createReminder(title: "Comprar pan", in: list, dueDayKey: 20_260_914)
        )

        store.toggleCompletion(for: task)

        let count1 = try allReminders(context).count
        #expect(count1 == 1)
    }

    @Test("Una tarea recurrente sin fecha no crea ninguna siguiente")
    func recurringWithoutDateCreatesNothing() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        // Una repetición sin vencimiento no tiene desde dónde contar. El
        // formulario no deja guardarla, pero el almacén tampoco debe inventarse
        // una fecha si llega así.
        let task = try #require(
            store.createReminder(title: "Algún día", in: list, recurrence: .daily)
        )

        store.toggleCompletion(for: task)

        let count2 = try allReminders(context).count
        #expect(count2 == 1)
    }

    @Test("Una subtarea no crea ninguna siguiente")
    func subtaskCreatesNothing() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let parent = try #require(store.createReminder(title: "Madre", in: list))

        // Quien se repite es la tarea madre. Duplicar una hija por su cuenta la
        // dejaría huérfana, fuera de la lista de comprobación a la que pertenece.
        let child = try #require(
            store.createReminder(
                title: "Hija",
                in: list,
                dueDayKey: 20_260_914,
                recurrence: .daily,
                parent: parent
            )
        )

        store.toggleCompletion(for: child)

        let count3 = try allReminders(context).count
        #expect(count3 == 2)
    }

    @Test("Desmarcar no crea ninguna siguiente")
    func uncompletingCreatesNothing() throws {
        let (store, context) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let task = try #require(
            store.createReminder(
                title: "Regar",
                in: list,
                dueDayKey: 20_260_914,
                recurrence: .daily
            )
        )

        store.toggleCompletion(for: task)
        let count4 = try allReminders(context).count
        #expect(count4 == 2)

        // Desmarcar la original no debe generar una tercera.
        store.toggleCompletion(for: task)
        let count5 = try allReminders(context).count
        #expect(count5 == 2)
    }

    // MARK: - Qué merece un aviso

    @Test("Solo las tareas con hora generan aviso")
    func onlyTimedRemindersNotify() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())

        let undated = try #require(store.createReminder(title: "Sin fecha", in: list))
        let allDay = try #require(
            store.createReminder(title: "Todo el día", in: list, dueDayKey: 20_260_914)
        )
        let timed = try #require(
            store.createReminder(
                title: "Dentista",
                in: list,
                dueDayKey: 20_260_914,
                dueMinuteOfDay: 10 * 60 + 30
            )
        )

        // Sin hora no hay momento al que avisar, y disparar a medianoche sería
        // inventarse uno.
        #expect(store.notificationRequest(for: undated) == nil)
        #expect(store.notificationRequest(for: allDay) == nil)

        let request = try #require(store.notificationRequest(for: timed))
        #expect(request.reminderID == timed.uuid)
        #expect(request.title == "Dentista")
        #expect(request.body == list.name)

        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireDate)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 14)
        #expect(parts.hour == 10)
        #expect(parts.minute == 30)
    }

    @Test("Una tarea completada no genera aviso")
    func completedRemindersDoNotNotify() throws {
        let (store, _) = try makeStore()
        let list = try #require(store.ensureDefaultList())
        let task = try #require(
            store.createReminder(
                title: "Llamar",
                in: list,
                dueDayKey: 20_260_914,
                dueMinuteOfDay: 11 * 60
            )
        )

        #expect(store.notificationRequest(for: task) != nil)

        store.toggleCompletion(for: task)
        #expect(store.notificationRequest(for: task) == nil)
    }
}
