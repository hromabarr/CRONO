import Foundation
import SwiftData
import Testing

@testable import Crono

/// Pruebas del desarme tal y como lo guarda y lo aplica el almacén de alarmas.
@MainActor
@Suite("Almacén de alarmas: desarme")
struct AlarmStoreTests {

    func makeStore() throws -> (store: AlarmStore, context: ModelContext) {
        let (store, context, _) = try makeStoreWithScheduler()
        return (store, context)
    }

    func makeStoreWithScheduler() throws -> (store: AlarmStore, context: ModelContext, scheduler: NoopAlarmScheduler) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.crono, configurations: configuration
        )
        let context = ModelContext(container)
        let scheduler = NoopAlarmScheduler()
        return (AlarmStore(context: context, scheduler: scheduler), context, scheduler)
    }

    /// Una alarma de todos los días con el plan por defecto, y la primera vez
    /// que va a sonar.
    ///
    /// La hora se elige a dos horas vista para que la primera mañana registrada
    /// sea siempre la próxima, corra el CI a la hora que corra.
    func makeInsistentAlarm(
        in store: AlarmStore
    ) async throws -> (alarm: AlarmItem, firstOccurrence: Date) {
        let minute = (AlarmStore.minuteOfDay(of: .now) + 120) % (24 * 60)
        let alarm = try #require(
            await store.create(
                minuteOfDay: minute,
                schedule: .everyDay,
                disarmMethod: .arithmetic,
                insistence: .default
            )
        )
        let first = try #require(
            InsistenceCalculator.occurrences(
                minuteOfDay: minute, schedule: .everyDay, from: .now, count: 1
            ).first
        )
        return (alarm, first)
    }

    // MARK: - Vueltas

    @Test("Armar registra las vueltas de las próximas mañanas")
    func armingRegistersFollowUps() async throws {
        let (store, _, scheduler) = try makeStoreWithScheduler()
        let (alarm, first) = try await makeInsistentAlarm(in: store)

        let perMorning = InsistencePlan.default.repeats
        let mornings = InsistenceCalculator.occurrencesAhead(for: .default)
        #expect(alarm.scheduledFollowUps.count == perMorning * mornings)
        #expect(scheduler.followUps.count == perMorning * mornings)

        let firstMorning = alarm.scheduledFollowUps.filter { $0.occurrence == first }
        let expected = InsistenceCalculator.fireDates(after: first, plan: .default)
        #expect(firstMorning.map(\.fireDate) == expected)
    }

    @Test("Solo espera desarme desde que suena hasta un minuto después de la última vuelta")
    func awaitingWindow() async throws {
        let (store, _) = try makeStore()
        let (alarm, first) = try await makeInsistentAlarm(in: store)
        let minute: TimeInterval = 60

        // Abrir la app cinco minutos antes no debe enseñar el desarme.
        #expect(alarm.occurrenceAwaitingDisarm(at: first.addingTimeInterval(-5 * minute)) == nil)
        #expect(alarm.occurrenceAwaitingDisarm(at: first.addingTimeInterval(4 * minute)) == first)
        #expect(alarm.occurrenceAwaitingDisarm(at: first.addingTimeInterval(13 * minute)) == first)
        #expect(alarm.occurrenceAwaitingDisarm(at: first.addingTimeInterval(14 * minute)) == nil)
    }

    @Test("Desarmar cancela esta mañana y deja las siguientes")
    func disarmCancelsOnlyThisMorning() async throws {
        let (store, _, scheduler) = try makeStoreWithScheduler()
        let (alarm, first) = try await makeInsistentAlarm(in: store)
        let ringing = first.addingTimeInterval(4 * 60)

        #expect(store.alarmAwaitingDisarm(at: ringing)?.uuid == alarm.uuid)

        await store.disarm(alarm, now: ringing)

        #expect(alarm.occurrenceAwaitingDisarm(at: ringing) == nil)
        #expect(store.alarmAwaitingDisarm(at: ringing) == nil)
        #expect(!alarm.scheduledFollowUps.contains { $0.occurrence == first })

        // Rellenar tras desarmar añade una mañana al final, nunca recupera la
        // que se acaba de desarmar.
        let perMorning = InsistencePlan.default.repeats
        let mornings = InsistenceCalculator.occurrencesAhead(for: .default)
        #expect(alarm.scheduledFollowUps.count == perMorning * mornings)
        #expect(scheduler.followUps.count == perMorning * mornings)
    }

    @Test("Mientras insiste no se puede apagar, cambiar ni borrar")
    func lockedWhileInsisting() async throws {
        let (store, context, scheduler) = try makeStoreWithScheduler()
        let (alarm, first) = try await makeInsistentAlarm(in: store)
        let registered = scheduler.followUps.count

        // Se finge que la primera mañana ya ha empezado moviendo sus vueltas al
        // presente: el almacén decide con la hora real.
        let shift = Date.now.addingTimeInterval(-60).timeIntervalSince(first)
        alarm.scheduledFollowUps = alarm.scheduledFollowUps.map { entry in
            guard entry.occurrence == first else { return entry }
            return ScheduledFollowUp(
                systemID: entry.systemID,
                occurrence: entry.occurrence.addingTimeInterval(shift),
                fireDate: entry.fireDate.addingTimeInterval(shift)
            )
        }
        try context.save()

        await store.setEnabled(false, for: alarm)
        #expect(alarm.isEnabled)
        #expect(store.failure != nil)

        store.failure = nil
        await store.delete(alarm)
        #expect(store.allAlarms().count == 1)
        #expect(store.failure != nil)

        #expect(scheduler.followUps.count == registered)
    }

    @Test("Hasta que se desarme registra una sola mañana")
    func untilDisarmedRegistersOneMorning() async throws {
        let (store, _, scheduler) = try makeStoreWithScheduler()
        let minute = (AlarmStore.minuteOfDay(of: .now) + 120) % (24 * 60)
        let alarm = try #require(
            await store.create(
                minuteOfDay: minute,
                disarmMethod: .scannedCode(value: "CRONO"),
                insistence: .untilDisarmed
            )
        )

        #expect(alarm.scheduledFollowUps.count == 60)
        #expect(scheduler.followUps.count == 60)
        #expect(Set(alarm.scheduledFollowUps.map(\.occurrence)).count == 1)
    }

    @Test("Desactivar la alarma cancela todas las vueltas")
    func disablingCancelsFollowUps() async throws {
        let (store, _, scheduler) = try makeStoreWithScheduler()
        let (alarm, _) = try await makeInsistentAlarm(in: store)

        await store.setEnabled(false, for: alarm)

        #expect(alarm.scheduledFollowUps.isEmpty)
        #expect(scheduler.followUps.isEmpty)
    }

    // MARK: - Lo que se guarda

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

    // MARK: - Sonido

    @Test("La alarma guarda su sonido y el de las vueltas")
    func soundsArePersisted() async throws {
        let (store, _) = try makeStore()
        let alarm = try #require(
            await store.create(
                minuteOfDay: 7 * 60,
                disarmMethod: .arithmetic,
                insistence: .default,
                sound: .bell,
                followUpSound: .siren
            )
        )
        #expect(alarm.sound == .bell)
        #expect(alarm.followUpSound == .siren)
        #expect(alarm.soundRaw == "campana")

        await store.update(
            alarm,
            minuteOfDay: alarm.minuteOfDay,
            label: alarm.label,
            schedule: alarm.schedule,
            snoozeEnabled: alarm.snoozeEnabled,
            disarmMethod: alarm.disarmMethod,
            disarmHint: alarm.disarmHint,
            insistence: alarm.insistence,
            sound: .beep
        )
        #expect(alarm.sound == .beep)
        // Lo que no se pasa no se toca.
        #expect(alarm.followUpSound == .siren)
    }

    @Test("Un sonido que no se conoce suena con el del sistema")
    func unknownSoundFallsBack() {
        #expect(AlarmSound(stored: "") == .system)
        #expect(AlarmSound(stored: "trompeta") == .system)
        #expect(AlarmSound.system.fileName == nil)
        #expect(AlarmSound.siren.fileName == "sirena.wav")
    }
}
