import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas del desarme tal y como lo guarda el almacén de alarmas.
@MainActor
@Suite("Almacén de alarmas: desarme")
struct AlarmStoreTests {

    func makeStore() throws -> (store: AlarmStore, context: ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.crono, configurations: configuration
        )
        let context = ModelContext(container)
        return (AlarmStore(context: context, scheduler: NoopAlarmScheduler()), context)
    }

    @Test("Una alarma con código guarda el código, la pista y el plan")
    func createWithScannedCode() async throws {
        let (store, _) = try makeStore()

        let alarm = try #require(
            await store.create(
                minuteOfDay: 7 * 60,
                disarmMethod: .scannedCode(value: "8410076472113"),
                disarmHint: "  el bote de champú ",
                insistence: .default
            )
        )

        #expect(alarm.disarmMethod == .scannedCode(value: "8410076472113"))
        #expect(alarm.disarmHint == "el bote de champú")
        #expect(alarm.insistence == .default)
        #expect(alarm.requiresDisarm)
    }

    @Test("Un método sin insistencia se guarda como solo parar")
    func methodWithoutInsistenceIsStop() async throws {
        let (store, _) = try makeStore()

        // Un método sin vueltas no pide nada: parar ya es el final. Guardarlo
        // dejaría un método que la interfaz enseña y que nunca se usa.
        let alarm = try #require(
            await store.create(
                minuteOfDay: 7 * 60,
                disarmMethod: .arithmetic,
                insistence: .none
            )
        )

        #expect(alarm.disarmMethod == .stop)
        #expect(alarm.insistence == .none)
        #expect(!alarm.requiresDisarm)
    }

    @Test("Volver a solo parar borra el plan y la pista")
    func updatingToStopClearsEverything() async throws {
        let (store, _) = try makeStore()
        let alarm = try #require(
            await store.create(
                minuteOfDay: 7 * 60,
                disarmMethod: .scannedCode(value: "CRONO"),
                disarmHint: "el baño",
                insistence: .default
            )
        )

        await store.update(
            alarm,
            minuteOfDay: alarm.minuteOfDay,
            label: alarm.label,
            schedule: alarm.schedule,
            snoozeEnabled: alarm.snoozeEnabled,
            disarmMethod: .stop,
            disarmHint: "el baño",
            insistence: .default
        )

        #expect(alarm.disarmMethod == .stop)
        #expect(alarm.disarmHint == "")
        #expect(alarm.insistence == .none)
    }

    @Test("La cuenta no guarda pista: no hay nada que ir a buscar")
    func arithmeticHasNoHint() async throws {
        let (store, _) = try makeStore()

        let alarm = try #require(
            await store.create(
                minuteOfDay: 7 * 60,
                disarmMethod: .arithmetic,
                disarmHint: "el baño",
                insistence: .default
            )
        )

        #expect(alarm.disarmMethod == .arithmetic)
        #expect(alarm.disarmHint == "")
    }
}
