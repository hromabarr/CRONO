import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas de lo que ofrecen Atajos y Siri.
@MainActor
@Suite("Atajos y Siri")
struct IntentTests {

    func makeStore() throws -> (store: HabitStore, context: ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema.crono, configurations: configuration)
        let context = ModelContext(container)
        return (HabitStore(context: context), context)
    }

    @Test("Solo se ofrecen los hábitos activos")
    func onlyActiveHabits() throws {
        let (store, context) = try makeStore()
        _ = store.createHabit(name: "Meditar")
        let old = try #require(store.createHabit(name: "Correr"))
        store.archive(old)

        let names = HabitEntityQuery.active(in: context).map(\.name)
        #expect(names == ["Meditar"])
    }

    @Test("Buscar por nombre ignora mayúsculas y tildes")
    func matchingIgnoresCaseAndAccents() throws {
        let (store, context) = try makeStore()
        _ = store.createHabit(name: "Meditación")
        _ = store.createHabit(name: "Leer")

        #expect(HabitEntityQuery.matching("meditacion", in: context).map(\.name) == ["Meditación"])
        #expect(HabitEntityQuery.matching("LEER", in: context).map(\.name) == ["Leer"])
        #expect(HabitEntityQuery.matching("  ", in: context).count == 2)
    }

    @Test("La frase de progreso dice lo que falta")
    func progressSentence() {
        #expect(TodayProgressIntent.sentence(for: .init(completed: 0, total: 0)) == "Hoy no tienes ningún hábito programado.")
        #expect(TodayProgressIntent.sentence(for: .init(completed: 3, total: 3)) == "Has hecho los 3 hábitos de hoy.")
        #expect(TodayProgressIntent.sentence(for: .init(completed: 1, total: 4)) == "Llevas 1 de 4 hábitos. Te quedan 3.")
    }
}
