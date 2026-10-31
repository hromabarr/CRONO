import Foundation

/// Lo que la app deja escrito para los widgets.
///
/// Se compila en los dos targets, la app y la extensión de widgets, así que
/// solo usa Foundation y tipos primitivos: nada de los modelos ni de SwiftData.
///
/// ## Por qué un resumen y no la base de datos
///
/// Un widget no puede abrir la base de la app sin moverla a un grupo de apps,
/// y moverla es arriesgar los datos de quien ya la tiene instalada. Así que la
/// base se queda donde está y la app escribe aquí lo justo para dibujar el día.
///
/// Si el grupo no existe —según cómo se haya firmado la app, puede no
/// existir—, `fileURL` es `nil`, la app no escribe y el widget dice «Abre
/// Crono» en vez de fallar.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.com.xilgar.crono"

    var writtenAt: Date
    /// El día en que se escribió, `yyyyMMdd`. Lo marcado vale solo ese día.
    var dayKey: Int
    var habits: [HabitItem]
    var alarms: [AlarmEntry]

    struct HabitItem: Codable, Equatable, Sendable {
        var name: String
        /// `HabitColor.rawValue`.
        var colorRaw: String
        /// Máscara de `WeekdaySet`: bit 0 domingo … bit 6 sábado.
        var weekdaysMask: Int
        /// Primer día en que cuenta, `yyyyMMdd`.
        var firstDay: Int
        /// Si ya estaba hecho el día de `dayKey`.
        var doneOnSnapshotDay: Bool
    }

    struct AlarmEntry: Codable, Equatable, Sendable {
        var label: String
        var minuteOfDay: Int
        var weekdaysMask: Int
    }

    // MARK: - Lectura y escritura

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget.json")
    }

    static func read(from url: URL? = WidgetSnapshot.fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func write(to url: URL? = WidgetSnapshot.fileURL) throws {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    // MARK: - El día

    struct DaySummary: Equatable, Sendable {
        var done: Int
        var total: Int
        /// Los que faltan, en el orden del usuario.
        var pending: [HabitItem]

        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    /// Cómo va el día de `date`.
    ///
    /// Si el resumen es de otro día —la app no se ha abierto desde ayer—, los
    /// hábitos programados se cuentan igual, pero todos como pendientes: lo
    /// marcado ayer no vale hoy. Así el widget acierta por la mañana sin
    /// esperar a que se abra la app.
    func summary(on date: Date, calendar: Calendar) -> DaySummary {
        let day = Self.dayKey(of: date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: date)
        let sameDay = day == dayKey

        var done = 0
        var total = 0
        var pending: [HabitItem] = []
        for habit in habits where habit.firstDay <= day && Self.mask(habit.weekdaysMask, contains: weekday) {
            total += 1
            if sameDay && habit.doneOnSnapshotDay {
                done += 1
            } else {
                pending.append(habit)
            }
        }
        return DaySummary(done: done, total: total, pending: pending)
    }

    /// La próxima alarma a partir de `date`, con la fecha en que sonará.
    func nextAlarm(after date: Date, calendar: Calendar) -> (alarm: AlarmEntry, date: Date)? {
        let startOfDay = calendar.startOfDay(for: date)
        var best: (alarm: AlarmEntry, date: Date)?

        for alarm in alarms {
            for offset in 0..<8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay),
                      Self.mask(alarm.weekdaysMask, contains: calendar.component(.weekday, from: day)),
                      let fire = calendar.date(
                          bySettingHour: alarm.minuteOfDay / 60,
                          minute: alarm.minuteOfDay % 60,
                          second: 0,
                          of: day
                      ),
                      fire > date
                else { continue }
                // La primera que suena de esta alarma; se queda si gana a la
                // mejor hasta ahora.
                if let current = best, current.date <= fire { break }
                best = (alarm, fire)
                break
            }
        }
        return best
    }

    static func dayKey(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    static func mask(_ mask: Int, contains weekday: Int) -> Bool {
        (1...7).contains(weekday) && mask & (1 << (weekday - 1)) != 0
    }
}
