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
        snoozeEnabled: Bool = true
    ) async -> AlarmItem? {
        let item = AlarmItem(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            minuteOfDay: minuteOfDay,
            schedule: schedule,
            snoozeEnabled: snoozeEnabled,
            sortIndex: nextSortIndex()
        )
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
        snoozeEnabled: Bool
    ) async {
        item.minuteOfDay = max(0, min(minuteOfDay, 24 * 60 - 1))
        item.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        item.schedule = schedule
        item.snoozeEnabled = snoozeEnabled

        guard save(action: "guardar la alarma") else {
            context.rollback()
            return
        }

        await syncWithSystem(item)
    }

    func setEnabled(_ isEnabled: Bool, for item: AlarmItem) async {
        item.isEnabled = isEnabled

        guard save(action: "cambiar la alarma") else {
            context.rollback()
            return
        }

        await syncWithSystem(item)
    }

    func delete(_ item: AlarmItem) async {
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
        guard let id = item.systemAlarmID else { return }

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
