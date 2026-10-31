import Foundation
import SwiftData
import WidgetKit

/// Escribe el resumen que leen los widgets y les pide redibujarse.
///
/// Se llama al salir de la app y al marcar desde Siri: son los momentos en que
/// lo que enseña el widget puede haberse quedado atrás.
@MainActor
enum WidgetSync {
    static func update(context: ModelContext, now: Date = .now) {
        // Sin grupo de apps no hay dónde escribir: ver `WidgetSnapshot`.
        guard WidgetSnapshot.fileURL != nil else { return }

        let habits = (try? context.fetch(HabitQueries.active)) ?? []
        let alarms = (try? context.fetch(AlarmQueries.all)) ?? []
        do {
            try makeSnapshot(habits: habits, alarms: alarms, now: now).write()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Un widget desactualizado no merece interrumpir al usuario.
        }
    }

    static func makeSnapshot(
        habits: [Habit],
        alarms: [AlarmItem],
        now: Date,
        calendar: Calendar = AppCalendar.current
    ) -> WidgetSnapshot {
        let today = calendar.dayKey(from: now)

        var habitItems: [WidgetSnapshot.HabitItem] = []
        for habit in habits where habit.isActive {
            habitItems.append(
                WidgetSnapshot.HabitItem(
                    name: habit.name,
                    colorRaw: habit.colorRaw,
                    weekdaysMask: habit.scheduledWeekdaysMask,
                    firstDay: habit.createdDayKey,
                    doneOnSnapshotDay: habit.isCompleted(on: today)
                )
            )
        }

        var alarmEntries: [WidgetSnapshot.AlarmEntry] = []
        for alarm in alarms where alarm.isSchedulable {
            alarmEntries.append(
                WidgetSnapshot.AlarmEntry(
                    label: alarm.displayLabel,
                    minuteOfDay: alarm.minuteOfDay,
                    weekdaysMask: alarm.scheduledWeekdaysMask
                )
            )
        }

        return WidgetSnapshot(writtenAt: now, dayKey: today, habits: habitItems, alarms: alarmEntries)
    }
}
