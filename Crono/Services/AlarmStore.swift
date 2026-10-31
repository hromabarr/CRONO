import Foundation
import SwiftData

/// Único punto de escritura sobre las alarmas.
///
/// Guarda en SwiftData y, por separado, pide al `AlarmScheduling` que registre o
/// dé de baja la alarma en el sistema. Los dos pasos están deliberadamente
/// separados: si el registro falla —permiso denegado, framework que no responde—
/// la alarma **sigue guardada** y la interfaz puede decir que no está activa en el
/// sistema. Perder lo que el usuario acaba de escribir porque el permiso no
/// estaba concedido sería mucho peor.
@MainActor
@Observable
final class AlarmStore {
    private let context: ModelContext
    private let scheduler: any AlarmScheduling

    var failure: StoreFailure?

    /// Último estado de permiso conocido, para que la interfaz pueda explicar por
    /// qué una alarma guardada no va a sonar.
    private(set) var authorization: AlarmAuthorization

    init(context: ModelContext, scheduler: any AlarmScheduling) {
        self.context = context
        self.scheduler = scheduler
        self.authorization = scheduler.authorization
    }

    // MARK: - Permiso

    @discardableResult
    func requestAuthorization() async -> AlarmAuthorization {
        let state = await scheduler.requestAuthorization()
        authorization = state
        return state
    }

    // MARK: - Altas y bajas

    @discardableResult
    func create(
        minuteOfDay: Int,
        label: String = "",
        schedule: WeekdaySet = .everyDay,
        snoozeEnabled: Bool = true,
        disarmMethod: DisarmMethod = .stop,
        disarmHint: String = "",
        insistence: InsistencePlan = .none
    ) async -> AlarmItem? {
        let item = AlarmItem(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            minuteOfDay: minuteOfDay,
            schedule: schedule,
            snoozeEnabled: snoozeEnabled,
            sortIndex: nextSortIndex()
        )
        Self.applyDisarm(disarmMethod, hint: disarmHint, insistence: insistence, to: item)
        context.insert(item)

        guard save(action: "crear la alarma") else {
            context.rollback()
            return nil
        }

        await syncWithSystem(item)
        return item
    }

    func update(
        _ item: AlarmItem,
        minuteOfDay: Int,
        label: String,
        schedule: WeekdaySet,
        snoozeEnabled: Bool,
        disarmMethod: DisarmMethod,
        disarmHint: String,
        insistence: InsistencePlan
    ) async {
        guard !isBlockedWhileInsisting(item, action: "guardar la alarma") else { return }

        item.minuteOfDay = max(0, min(minuteOfDay, 24 * 60 - 1))
        item.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        item.schedule = schedule
        item.snoozeEnabled = snoozeEnabled
        Self.applyDisarm(disarmMethod, hint: disarmHint, insistence: insistence, to: item)

        guard save(action: "guardar la alarma") else {
            context.rollback()
            return
        }

        await syncWithSystem(item)
    }

    /// Guarda el desarme y la insistencia como un todo.
    ///
    /// Van juntos porque por separado no tienen sentido: insistir sin método de
    /// desarme sería una alarma que vuelve y no hay forma de callar del todo, y
    /// un método sin insistencia no pide nada, porque parar ya es el final. Sin
    /// método se guarda «solo parar» con el plan y la pista vacíos, para que no
    /// quede un plan huérfano que reaparezca al volver a elegir un método.
    private static func applyDisarm(
        _ method: DisarmMethod,
        hint: String,
        insistence: InsistencePlan,
        to item: AlarmItem
    ) {
        if method.requiresAction, insistence.isActive {
            item.disarmMethod = method
            item.disarmHint = method == .arithmetic ? "" : hint.trimmingCharacters(in: .whitespacesAndNewlines)
            item.insistence = insistence
        } else {
            item.disarmMethod = .stop
            item.disarmHint = ""
            item.insistence = .none
        }
    }

    func setEnabled(_ isEnabled: Bool, for item: AlarmItem) async {
        guard !isBlockedWhileInsisting(item, action: "cambiar la alarma") else { return }

        item.isEnabled = isEnabled

        guard save(action: "cambiar la alarma") else {
            context.rollback()
            return
        }

        await syncWithSystem(item)
    }

    func delete(_ item: AlarmItem) async {
        guard !isBlockedWhileInsisting(item, action: "eliminar la alarma") else { return }

        // Se da de baja del sistema **antes** de borrarla: después ya no habría
        // de dónde leer el identificador, y quedaría una alarma sonando por algo
        // que el usuario cree eliminado.
        await unschedule(item)

        context.delete(item)
        if !save(action: "eliminar la alarma") { context.rollback() }
    }

    // MARK: - Sincronización con el sistema

    /// Deja el sistema acorde con lo que dice la alarma guardada.
    ///
    /// Siempre da de baja primero y vuelve a registrar: cambiar la hora o los días
    /// de una alarma ya registrada no se puede hacer en sitio, y dejar la vieja
    /// puesta significaría dos alarmas sonando.
    private func syncWithSystem(_ item: AlarmItem) async {
        refreshAuthorization()

        await unschedule(item)

        guard item.isSchedulable else { return }

        // Sin permiso concedido no se intenta registrar. No es solo para evitar
        // un error: en AlarmKit el propio intento de programar hace aparecer el
        // diálogo del sistema, así que sin esta guarda cualquier escritura pide
        // el permiso por la puerta de atrás — incluida la resincronización del
        // arranque, que lo sacaba nada más abrir la app.
        //
        // La alarma queda guardada y sin registrar, y la interfaz lo dice.
        guard authorization == .authorized else { return }

        do {
            let id = try await scheduler.schedule(item)
            item.systemAlarmID = id
            _ = save(action: "activar la alarma")
            await topUpFollowUps(item, now: .now)
        } catch {
            // La alarma queda guardada y sin registrar. La interfaz lo indica.
            item.systemAlarmID = nil
            _ = save(action: "activar la alarma")
            failure = StoreFailure(
                action: "activar la alarma en el sistema",
                reason: error.localizedDescription
            )
        }
    }

    private func unschedule(_ item: AlarmItem) async {
        let now = Date.now
        for entry in item.scheduledFollowUps {
            await cancelFollowUp(entry, now: now)
        }
        item.followUpAlarmIDsRaw = ""

        guard let id = item.systemAlarmID else {
            _ = save(action: "desactivar la alarma")
            return
        }

        do {
            try await scheduler.cancel(systemAlarmID: id)
        } catch {
            failure = StoreFailure(
                action: "desactivar la alarma en el sistema",
                reason: error.localizedDescription
            )
        }

        item.systemAlarmID = nil
        _ = save(action: "desactivar la alarma")
    }

    /// Vuelve a registrar todas las alarmas activas.
    ///
    /// Se llama al arrancar: las alarmas del sistema pueden haberse perdido al
    /// reinstalar la app, y una alarma que el usuario ve activada tiene que
    /// sonar.
    func resyncAll() async {
        refreshAuthorization()
        // Si el permiso no está concedido no hay nada que resincronizar, y
        // entrar en `syncWithSystem` provocaría el diálogo del sistema al
        // arrancar la app.
        guard authorization == .authorized else { return }

        for item in allAlarms() where item.isSchedulable && item.systemAlarmID == nil {
            await syncWithSystem(item)
        }

        // Las vueltas se registran solo unas mañanas por delante, así que cada
        // arranque es la ocasión de rellenarlas.
        for item in allAlarms() where item.systemAlarmID != nil {
            await topUpFollowUps(item, now: .now)
        }
    }

    // MARK: - Insistencia y desarme

    /// La alarma que está sonando —o acaba de sonar— y espera que se desarme.
    func alarmAwaitingDisarm(at now: Date = .now) -> AlarmItem? {
        allAlarms().first { $0.occurrenceAwaitingDisarm(at: now) != nil }
    }

    /// Si la alarma está insistiendo y por eso no se puede tocar.
    ///
    /// Cambiarla, apagarla o borrarla cancela sus vueltas, así que permitirlo
    /// mientras suena sería una forma de desarmarla sin escanear nada. La única
    /// salida mientras insiste es desarmarla.
    private func isBlockedWhileInsisting(_ item: AlarmItem, action: String, now: Date = .now) -> Bool {
        guard item.occurrenceAwaitingDisarm(at: now) != nil else { return false }
        failure = StoreFailure(
            action: action,
            reason: "Está sonando y espera que la desarmes. Desármala primero."
        )
        return true
    }

    /// Cancela las vueltas que quedan de esta mañana.
    ///
    /// Solo las de esta mañana: las de los días siguientes siguen registradas,
    /// porque desarmar hoy no es apagar la insistencia.
    func disarm(_ item: AlarmItem, now: Date = .now) async {
        guard let occurrence = item.occurrenceAwaitingDisarm(at: now) else { return }

        let entries = item.scheduledFollowUps
        for entry in entries where entry.occurrence == occurrence {
            await cancelFollowUp(entry, now: now)
        }
        item.scheduledFollowUps = entries.filter { $0.occurrence != occurrence }
        _ = save(action: "desarmar la alarma")

        await topUpFollowUps(item, now: now)
    }

    /// Quita las vueltas que ya sonaron y registra las de las próximas mañanas.
    ///
    /// Solo añade mañanas que **aún no han empezado**. Es lo que impide que una
    /// mañana recién desarmada recupere sus vueltas al rellenar, y que instalar
    /// la app con una alarma sonando empiece a insistir a mitad.
    private func topUpFollowUps(_ item: AlarmItem, now: Date) async {
        var entries = item.scheduledFollowUps

        let expired = entries.filter { $0.fireDate.addingTimeInterval(60) < now }
        for entry in expired {
            await cancelFollowUp(entry, now: now)
        }
        entries.removeAll { expired.contains($0) }

        if item.requiresDisarm, item.isSchedulable, item.systemAlarmID != nil {
            let covered = Set(entries.map(\.occurrence))
            let occurrences = InsistenceCalculator.occurrences(
                minuteOfDay: item.minuteOfDay,
                schedule: item.schedule,
                from: now.addingTimeInterval(1),
                count: InsistenceCalculator.occurrencesAhead(for: item.insistence)
            )

            register: for occurrence in occurrences where !covered.contains(occurrence) {
                let dates = InsistenceCalculator.fireDates(after: occurrence, plan: item.insistence)
                for (index, date) in dates.enumerated() {
                    do {
                        let id = try await scheduler.scheduleFollowUp(of: item, at: date, ordinal: index + 1)
                        entries.append(ScheduledFollowUp(systemID: id, occurrence: occurrence, fireDate: date))
                    } catch {
                        // Lo registrado hasta aquí se guarda, para poder
                        // cancelarlo; el próximo arranque reintenta el resto.
                        failure = StoreFailure(
                            action: "programar las vueltas de la alarma",
                            reason: error.localizedDescription
                        )
                        break register
                    }
                }
            }
        }

        item.scheduledFollowUps = entries
        _ = save(action: "guardar las vueltas de la alarma")
    }

    /// Da de baja una vuelta.
    ///
    /// Si ya sonó, un fallo al cancelarla no se cuenta: el sistema puede haberla
    /// olvidado ya, y avisar de ello sería una alerta por nada. Si aún no ha
    /// sonado, sí, porque va a sonar por una alarma que el usuario cree resuelta.
    private func cancelFollowUp(_ entry: ScheduledFollowUp, now: Date) async {
        do {
            try await scheduler.cancel(systemAlarmID: entry.systemID)
        } catch let error where entry.fireDate > now {
            failure = StoreFailure(
                action: "cancelar una vuelta de la alarma",
                reason: error.localizedDescription
            )
        } catch {}
    }

    /// Relee el permiso del planificador.
    ///
    /// El estado lo mantiene el sistema y puede cambiar fuera de la app —el
    /// usuario lo concede o lo revoca en Ajustes—, así que la copia local se
    /// refresca antes de decidir si merece la pena intentar registrar algo.
    private func refreshAuthorization() {
        authorization = scheduler.authorization
    }

    // MARK: - Consultas

    func allAlarms() -> [AlarmItem] {
        do {
            return try context.fetch(AlarmQueries.all)
        } catch {
            failure = StoreFailure(
                action: "cargar las alarmas",
                reason: error.localizedDescription
            )
            return []
        }
    }

    /// La siguiente alarma que va a sonar.
    ///
    /// La lógica vive en `AlarmItem.next(from:)`, que es pura: así la pantalla
    /// Hoy puede alimentarla desde su `@Query` sin consultar la base en cada
    /// redibujado, y se puede probar con una fecha fija.
    func nextAlarm(
        from now: Date = .now,
        calendar: Calendar = AppCalendar.current
    ) -> AlarmItem? {
        AlarmItem.next(from: allAlarms(), now: now, calendar: calendar)
    }

    static func minuteOfDay(of date: Date, calendar: Calendar = AppCalendar.current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Internos

    private func nextSortIndex() -> Int {
        var highest = -1
        for item in allAlarms() where item.sortIndex > highest {
            highest = item.sortIndex
        }
        return highest + 1
    }

    private func save(action: String) -> Bool {
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
