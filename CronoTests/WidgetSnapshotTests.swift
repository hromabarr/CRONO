import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas del resumen que la app deja a los widgets.
@MainActor
@Suite("Resumen para widgets")
struct WidgetSnapshotTests {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// Lunes 14 de septiembre de 2026: dos hábitos diarios, uno hecho, y uno
    /// solo de sábados.
    var snapshot: WidgetSnapshot {
        WidgetSnapshot(
            writtenAt: date(14, 10),
            dayKey: 20260914,
            habits: [
                .init(name: "Meditar", colorRaw: "indigo", weekdaysMask: 127, firstDay: 20260901, doneOnSnapshotDay: true),
                .init(name: "Agua", colorRaw: "teal", weekdaysMask: 127, firstDay: 20260901, doneOnSnapshotDay: false),
                .init(name: "Limpiar", colorRaw: "green", weekdaysMask: 1 << 6, firstDay: 20260901, doneOnSnapshotDay: false)
            ],
            alarms: [
                .init(label: "Despertar", minuteOfDay: 7 * 60, weekdaysMask: 127),
                .init(label: "Siesta", minuteOfDay: 16 * 60, weekdaysMask: 1 << 1)
            ]
        )
    }

    @Test("El mismo día cuenta lo marcado")
    func sameDay() {
        let summary = snapshot.summary(on: date(14, 20), calendar: calendar)

        #expect(summary.done == 1)
        #expect(summary.total == 2)
        #expect(summary.pending.map(\.name) == ["Agua"])
    }

    @Test("Al día siguiente todo vuelve a estar pendiente")
    func nextDayResets() {
        let summary = snapshot.summary(on: date(15, 8), calendar: calendar)

        #expect(summary.done == 0)
        #expect(summary.total == 2)
    }

    @Test("Solo cuentan los hábitos programados ese día")
    func onlyScheduled() {
        // Sábado 19: entra también el de los sábados.
        #expect(snapshot.summary(on: date(19, 9), calendar: calendar).total == 3)
    }

    @Test("La próxima alarma es la más cercana, aunque sea de otro día")
    func nextAlarm() {
        // Lunes 14 a las 12:00: la siesta de los lunes a las 16:00.
        #expect(snapshot.nextAlarm(after: date(14, 12), calendar: calendar)?.alarm.label == "Siesta")
        // Lunes a las 17:00: ya sonó; la siguiente es despertar el martes.
        let next = snapshot.nextAlarm(after: date(14, 17), calendar: calendar)
        #expect(next?.alarm.label == "Despertar")
        #expect(next?.date == date(15, 7))
    }

    @Test("Ida y vuelta por disco")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }

        try snapshot.write(to: url)

        // ISO 8601 guarda al segundo, y la fecha de ejemplo no tiene fracción.
        #expect(WidgetSnapshot.read(from: url) == snapshot)
    }

    @Test("El resumen sale de los hábitos activos y las alarmas que suenan")
    func makeFromModels() throws {
        let container = try ModelContainer(for: Schema.crono, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = HabitStore(context: context)
        let done = try #require(store.createHabit(name: "Meditar"))
        _ = store.createHabit(name: "Agua", targetCount: 8)
        let archived = try #require(store.createHabit(name: "Viejo"))
        store.archive(archived)
        let today = done.createdDayKey
        store.toggleCompletion(for: done, on: today, today: today)

        let alarm = AlarmItem(minuteOfDay: 7 * 60)
        let off = AlarmItem(minuteOfDay: 8 * 60, isEnabled: false)
        context.insert(alarm)
        context.insert(off)

        let habits = try context.fetch(HabitQueries.active)
        let snapshot = WidgetSync.makeSnapshot(habits: habits, alarms: [alarm, off], now: .now)

        #expect(snapshot.habits.map(\.name).sorted() == ["Agua", "Meditar"])
        #expect(snapshot.habits.first { $0.name == "Meditar" }?.doneOnSnapshotDay == true)
        #expect(snapshot.alarms.count == 1)
    }
}
