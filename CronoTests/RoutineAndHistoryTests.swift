import Foundation
import SwiftData
import Testing

@testable import Crono

@MainActor
@Suite("Rutinas y corrección del historial")
struct RoutineAndHistoryTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        result.firstWeekday = 2
        return result
    }

    private func date(_ key: DayKey) -> Date {
        calendar.date(fromDayKey: key)!.addingTimeInterval(12 * 60 * 60)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema.crono, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test("La rutina respeta días, orden y marcas al retomarla")
    func resumeRoutine() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = HabitStore(context: context, calendar: calendar)
        let day = 20260914 // Monday
        let first = Habit(name: "Agua", createdAt: date(day), sortIndex: 0, routine: .morning)
        let second = Habit(name: "Meditar", createdAt: date(day), sortIndex: 1, routine: .morning)
        let night = Habit(name: "Leer", createdAt: date(day), routine: .evening)
        // Con sortIndex explícito: sin él se quedaba en 0, empatado con "Agua",
        // y quién era el siguiente el martes dependía del orden del fetch.
        let tomorrow = Habit(name: "Correr", schedule: [.tuesday], createdAt: date(day), sortIndex: 2, routine: .morning)
        let archived = Habit(name: "Archivado", createdAt: date(day), archivedAt: date(day), routine: .morning)
        for habit in [second, night, tomorrow, archived, first] { context.insert(habit) }
        try context.save()

        let all = try context.fetch(FetchDescriptor<Habit>())
        let initial = RoutineProgress(routine: .morning, habits: all, day: day)
        #expect(initial.habits.map(\.name) == ["Agua", "Meditar"])
        #expect(initial.next?.uuid == first.uuid)
        store.toggleCompletion(for: first, on: day, today: day)

        let otherContext = ModelContext(container)
        let persisted = try otherContext.fetch(FetchDescriptor<Habit>())
        let resumed = RoutineProgress(routine: .morning, habits: persisted, day: day)
        #expect(resumed.completedCount == 1)
        #expect(resumed.next?.uuid == second.uuid)
        #expect(resumed.actionTitle == "Continuar rutina")

        store.toggleCompletion(for: second, on: day, today: day)
        let finished = RoutineProgress(routine: .morning, habits: all, day: day)
        #expect(finished.next == nil)
        #expect(finished.completedCount == 2)
        let newDay = RoutineProgress(routine: .morning, habits: all, day: 20260915)
        #expect(newDay.completedCount == 0)
        #expect(newDay.next?.uuid == first.uuid)
        store.toggleCompletion(for: first, on: day, today: day)
        #expect(RoutineProgress(routine: .morning, habits: all, day: day).next?.uuid == first.uuid)
    }

    @Test("El orden de la rutina es el mismo aunque los hábitos lleguen barajados")
    func routineOrderIsTotal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = 20260914

        // Los tres empatan en sortIndex —el valor por defecto es 0, así que
        // empatar es lo fácil— y dos de ellos también en fecha de creación. Sin
        // un orden total, cuál sale primero depende del orden del fetch, y la
        // rutina diría «Siguiente: Correr» una vez y «Siguiente: Agua» la
        // siguiente sin que el usuario haya tocado nada.
        let agua = Habit(name: "Agua", createdAt: date(day), routine: .morning)
        let correr = Habit(name: "Correr", createdAt: date(day), routine: .morning)
        let meditar = Habit(name: "Meditar", createdAt: date(day), routine: .morning)
        for habit in [agua, correr, meditar] { context.insert(habit) }
        try context.save()

        let arrangements: [[Habit]] = [
            [agua, correr, meditar],
            [meditar, correr, agua],
            [correr, agua, meditar]
        ]

        for arrangement in arrangements {
            let progress = RoutineProgress(routine: .morning, habits: arrangement, day: day)
            let names = progress.habits.map(\.name)
            #expect(names == ["Agua", "Correr", "Meditar"])
        }
    }

    @Test("Crear y editar guarda la rutina sin borrar sus registros")
    func formPersistsRoutine() throws {
        let container = try makeContainer()
        let store = HabitStore(context: container.mainContext)
        let draft = HabitFormViewModel(mode: .create, store: store, routine: .morning)
        draft.name = "Meditar"
        #expect(draft.save())
        let habit = try #require(store.activeHabits().first)
        let day = habit.createdDayKey
        store.toggleCompletion(for: habit, on: day, today: day)
        let edit = HabitFormViewModel(mode: .edit(habit), store: store)
        #expect(edit.routine == .morning)
        edit.routine = .evening
        #expect(edit.save())
        let persisted = try ModelContext(container).fetch(FetchDescriptor<Habit>())
        #expect(persisted.first?.routine == .evening)
        #expect(persisted.first?.isCompleted(on: day) == true)
        // An unrelated update must preserve the assigned routine.
        store.update(habit, name: "Meditar", notes: "Respirar", color: .green, schedule: .everyDay)
        #expect(habit.routine == .evening)
    }

    @Test("Un hábito migrado o con rutina desconocida queda durante el día")
    func unassignedRoutine() {
        let habit = Habit(name: "Leer")
        habit.routineRaw = nil
        #expect(habit.routine == .anytime)
        habit.routineRaw = "future-routine"
        #expect(habit.routine == .anytime)
    }

    @Test("Corregir ayer actualiza calendario, rachas y permite deshacer")
    func correctionUpdatesHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = HabitStore(context: context, calendar: calendar)
        let habit = Habit(name: "Leer", createdAt: date(20260913))
        context.insert(habit)
        try context.save()
        let history = HistoryViewModel(calendar: calendar, today: 20260915)
        store.toggleCompletion(for: habit, on: 20260913, today: 20260915)
        #expect(history.aggregateStats(for: [habit]).currentStreak == 0)
        store.toggleCompletion(for: habit, on: 20260914, today: 20260915)
        #expect(history.aggregateStats(for: [habit]).currentStreak == 2)
        #expect(history.cells(for: [habit]).first { $0.dayKey == 20260914 }?.fraction == 1)
        #expect(try context.fetchCount(FetchDescriptor<HabitCompletion>()) == 2)
        store.toggleCompletion(for: habit, on: 20260914, today: 20260915)
        #expect(history.aggregateStats(for: [habit]).currentStreak == 0)
        #expect(history.cells(for: [habit]).first { $0.dayKey == 20260914 }?.fraction == 0)
        #expect(try context.fetchCount(FetchDescriptor<HabitCompletion>()) == 1)
    }

    @Test("Los archivados conservan sus días y no generan incumplimientos posteriores")
    func archivedHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = HabitStore(context: context, calendar: calendar)
        let habit = Habit(name: "Guitarra", createdAt: date(20260910), archivedAt: date(20260911))
        context.insert(habit)
        try context.save()
        store.toggleCompletion(for: habit, on: 20260910, today: 20260915)
        store.toggleCompletion(for: habit, on: 20260911, today: 20260915)
        let history = HistoryViewModel(calendar: calendar, today: 20260915)
        let stats = history.aggregateStats(for: [habit])
        #expect(stats.currentStreak == 2)
        #expect(stats.bestStreak == 2)
        #expect(stats.completionRate == 1)
        #expect(history.streaks(for: [habit]).first?.streak == 2)
        #expect(history.cells(for: [habit]).first { $0.dayKey == 20260911 }?.fraction == 1)
        #expect(history.cells(for: [habit]).first { $0.dayKey == 20260912 }?.fraction == 0)
        #expect(!habit.isScheduled(on: 20260912, calendar: calendar))

        store.toggleCompletion(for: habit, on: 20260912, today: 20260915)
        #expect(store.failure != nil)
        #expect(!habit.isCompleted(on: 20260912))
        // Valid correction remains possible after a rejected write.
        store.toggleCompletion(for: habit, on: 20260911, today: 20260915)
        #expect(store.failure == nil)
        #expect(!habit.isCompleted(on: 20260911))
    }

    @Test("No se admiten fechas inválidas, futuras ni anteriores al alta")
    func rejectsInvalidDates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = HabitStore(context: context, calendar: calendar)
        let habit = Habit(name: "Leer", createdAt: date(20260914))
        context.insert(habit)
        try context.save()
        for day in [20260230, 20260916, 20260913] {
            store.toggleCompletion(for: habit, on: day, today: 20260915)
            #expect(store.failure != nil)
        }
        #expect(try context.fetchCount(FetchDescriptor<HabitCompletion>()) == 0)
    }

    @Test("Hoy conserva la alarma aunque no haya hábitos ni tareas")
    func alarmOnFreeDay() {
        let alarm = AlarmItem(minuteOfDay: 420)
        let withAlarm = TodayDigest(scheduledHabits: [], reminders: [], nextAlarm: alarm, today: 20260915, nowMinuteOfDay: 360)
        #expect(withAlarm.isEmpty)
        #expect(!withAlarm.showsEmptyState)
        let empty = TodayDigest(scheduledHabits: [], reminders: [], nextAlarm: nil, today: 20260915, nowMinuteOfDay: 360)
        #expect(empty.showsEmptyState)
    }
}
