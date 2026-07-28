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
        await unschedule(item)

        guard item.isSchedulable else { return }

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
        for item in allAlarms() where item.isSchedulable && item.systemAlarmID == nil {
            await syncWithSystem(item)
        }
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

    /// La siguiente alarma que va a sonar, para enseñarla en la pantalla Hoy.
    ///
    /// Recorre los siete próximos días en lugar de calcular con aritmética
    /// modular: son 7 iteraciones y el código se lee sin tener que confiar en él.
    func nextAlarm(
        from now: Date = .now,
        calendar: Calendar = AppCalendar.current
    ) -> AlarmItem? {
        let alarms = allAlarms().filter(\.isSchedulable)
        guard !alarms.isEmpty else { return nil }

        let nowMinute = Self.minuteOfDay(of: now, calendar: calendar)
        let todayWeekday = calendar.component(.weekday, from: now)

        for dayOffset in 0..<7 {
            let weekday = (todayWeekday - 1 + dayOffset) % 7 + 1
            let candidates = alarms
                .filter { $0.schedule.contains(weekday: weekday) }
                .filter { dayOffset > 0 || $0.minuteOfDay > nowMinute }
                .sorted { $0.minuteOfDay < $1.minuteOfDay }

            if let first = candidates.first { return first }
        }

        return nil
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
