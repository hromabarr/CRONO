import Foundation
import SwiftData

/// Datos de ejemplo para las previsualizaciones de Xcode.
///
/// Todo se monta en un contenedor en memoria: las previsualizaciones nunca tocan
/// la base real, así que se puede marcar y desmarcar sin ensuciar los datos del
/// dispositivo.
///
/// ## Por qué no va entre `#if DEBUG`
///
/// Los bloques `#Preview` se compilan en todas las configuraciones, también en
/// Release. Si este tipo solo existiera en Debug, cada `#Preview` que lo usa
/// dejaría de compilar al generar el `.ipa`. El coste de no aislarlo es un poco
/// de código de ejemplo inerte en el binario; el de aislarlo sería tener que
/// envolver quince bloques de previsualización.
@MainActor
enum PreviewData {

    /// Contenedor en memoria con un historial plausible de dos meses.
    static func container() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Habit.self, HabitCompletion.self, ReminderList.self, Reminder.self, AlarmItem.self,
                configurations: configuration
            )
        } catch {
            fatalError("No se pudo crear el contenedor de previsualización: \(error)")
        }

        populate(container.mainContext)
        return container
    }

    /// Contenedor vacío, para previsualizar los estados sin contenido.
    static func emptyContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: Habit.self, HabitCompletion.self, ReminderList.self, Reminder.self, AlarmItem.self,
                configurations: configuration
            )
        } catch {
            fatalError("No se pudo crear el contenedor de previsualización: \(error)")
        }
    }

    static func store(for container: ModelContainer) -> HabitStore {
        HabitStore(context: container.mainContext)
    }

    static func reminderStore(for container: ModelContainer) -> ReminderStore {
        ReminderStore(context: container.mainContext)
    }

    /// El planificador es el que no toca el sistema: una previsualización no debe
    /// registrar alarmas de verdad en el dispositivo.
    static func alarmStore(for container: ModelContainer) -> AlarmStore {
        AlarmStore(context: container.mainContext, scheduler: NoopAlarmScheduler())
    }

    // MARK: - Contenido

    /// Inserta el contenido de ejemplo en un contexto cualquiera.
    ///
    /// Es accesible desde fuera porque las capturas automáticas en CI la usan
    /// para poblar la app real antes de fotografiarla: un simulador recién
    /// instalado no tiene datos y todas las capturas saldrían del estado vacío.
    static func seed(into context: ModelContext) {
        populate(context)
    }

    private static func populate(_ context: ModelContext) {
        let calendar = AppCalendar.current
        let today = Date.now
        let createdAt = calendar.date(byAdding: .day, value: -60, to: today) ?? today

        // Se reparte una mezcla de hábitos diarios y por días concretos, para
        // que las previsualizaciones ejerciten los dos caminos.
        let specs: [(String, String, HabitColor, WeekdaySet, Int)] = [
            ("Meditar 10 minutos", "Nada más levantarme", .green, .everyDay, 92),
            ("Beber 2 litros de agua", "", .teal, .everyDay, 78),
            ("Leer 20 páginas", "Antes de dormir", .indigo, .everyDay, 85),
            ("Correr", "5 km suaves", .orange, [.monday, .wednesday, .friday], 70),
            ("Estudiar inglés", "30 min de repaso", .purple, .weekdays, 64)
        ]

        for (index, spec) in specs.enumerated() {
            let (name, notes, color, schedule, percent) = spec
            let habit = Habit(
                name: name,
                notes: notes,
                color: color,
                schedule: schedule,
                createdAt: createdAt,
                sortIndex: index
            )
            context.insert(habit)

            addCompletions(
                to: habit,
                from: createdAt,
                to: today,
                percent: percent,
                seed: index,
                // Los dos primeros quedan hechos hoy y los tres últimos
                // pendientes. Un juego de datos donde todo está cumplido deja
                // el anillo siempre al 100 % y no enseña ni el progreso parcial
                // ni los toggles sin marcar, que es la mitad de la pantalla.
                completeToday: index < 2,
                calendar: calendar,
                context: context
            )
        }

        // Un hábito archivado, para que la sección se vea poblada.
        let archived = Habit(
            name: "Tocar la guitarra",
            notes: "Quince minutos de escalas",
            color: .yellow,
            schedule: .everyDay,
            createdAt: createdAt,
            archivedAt: calendar.date(byAdding: .day, value: -20, to: today),
            sortIndex: specs.count
        )
        context.insert(archived)

        populateReminders(context, calendar: calendar, today: today)
        populateAlarms(context)

        try? context.save()
    }

    /// Alarmas de ejemplo, con casos distintos a propósito.
    ///
    /// Una activada y registrada, una desactivada, y una activa **sin** registrar
    /// en el sistema — que es el estado que la interfaz tiene que saber contar,
    /// porque es el peor: el usuario cree que va a sonar y no va a sonar.
    private static func populateAlarms(_ context: ModelContext) {
        let specs: [(String, Int, WeekdaySet, Bool, UUID?)] = [
            ("Despertar", 7 * 60, .weekdays, true, UUID()),
            ("Fin de semana", 9 * 60 + 30, .weekend, true, UUID()),
            ("Siesta", 15 * 60, [], false, nil),
            ("Gimnasio", 6 * 60 + 45, [.tuesday, .thursday], true, nil)
        ]

        for (index, spec) in specs.enumerated() {
            let (label, minute, schedule, enabled, systemID) = spec
            let alarm = AlarmItem(
                label: label,
                minuteOfDay: minute,
                schedule: schedule,
                isEnabled: enabled,
                sortIndex: index,
                systemAlarmID: systemID
            )
            context.insert(alarm)
        }
    }

    /// Listas y tareas de ejemplo.
    ///
    /// Se reparten a propósito casos distintos: sin fecha, atrasada, para hoy con
    /// hora, con prioridad, con bandera y con subtareas. Un juego de datos donde
    /// todas las tareas son iguales no enseña ninguno de esos estados.
    private static func populateReminders(
        _ context: ModelContext,
        calendar: Calendar,
        today: Date
    ) {
        let todayKey = calendar.dayKey(from: today)
        let yesterday = calendar.dayKey(todayKey, offsetByDays: -1)
        let tomorrow = calendar.dayKey(todayKey, offsetByDays: 1)

        let personal = ReminderList(name: "Personal", color: .blue, symbolName: "person", sortIndex: 0)
        let work = ReminderList(name: "Trabajo", color: .orange, symbolName: "briefcase", sortIndex: 1)
        context.insert(personal)
        context.insert(work)

        let specs: [(String, ReminderList, DayKey?, Int?, ReminderPriority, Bool)] = [
            ("Llamar al dentista", personal, yesterday, 10 * 60, .high, true),
            ("Comprar pan", personal, todayKey, nil, .none, false),
            ("Recoger el paquete", personal, todayKey, 18 * 60 + 30, .medium, false),
            ("Cambiar las bombillas", personal, nil, nil, .none, false),
            ("Revisar el informe", work, todayKey, 9 * 60, .high, false),
            ("Responder correos", work, tomorrow, nil, .low, false),
            ("Preparar la reunión", work, nil, nil, .none, true)
        ]

        for (index, spec) in specs.enumerated() {
            let (title, list, dayKey, minute, priority, flagged) = spec
            let reminder = Reminder(
                title: title,
                sortIndex: index,
                dueDayKey: dayKey,
                dueMinuteOfDay: minute,
                priority: priority,
                isFlagged: flagged
            )
            context.insert(reminder)
            reminder.list = list
        }

        // Una tarea con subtareas, para que se vea el indicador «1 de 3».
        let move = Reminder(title: "Preparar la mudanza", sortIndex: specs.count, dueDayKey: tomorrow)
        context.insert(move)
        move.list = personal

        let steps = ["Pedir cajas", "Reservar furgoneta", "Avisar al portero"]
        for (index, step) in steps.enumerated() {
            let subtask = Reminder(
                title: step,
                isCompleted: index == 0,
                completedAt: index == 0 ? today : nil,
                sortIndex: index
            )
            context.insert(subtask)
            subtask.list = personal
            subtask.parent = move
        }

        // Y una completada, para que la sección plegable no salga vacía.
        let done = Reminder(
            title: "Pagar el recibo del agua",
            isCompleted: true,
            completedAt: calendar.date(byAdding: .hour, value: -3, to: today),
            sortIndex: 99
        )
        context.insert(done)
        done.list = personal
    }

    /// Rellena el historial de un hábito de forma determinista.
    ///
    /// El patrón se deriva del índice, no de `Bool.random()`: una previsualización
    /// que cambia en cada redibujado hace imposible comparar dos versiones de una
    /// vista, que es justo para lo que sirven.
    private static func addCompletions(
        to habit: Habit,
        from start: Date,
        to end: Date,
        percent: Int,
        seed: Int,
        completeToday: Bool,
        calendar: Calendar,
        context: ModelContext
    ) {
        let startKey = calendar.dayKey(from: start)
        let endKey = calendar.dayKey(from: end)

        for (offset, dayKey) in calendar.dayKeys(from: startKey, to: endKey).enumerated() {
            guard let weekday = calendar.weekday(fromDayKey: dayKey),
                  habit.schedule.contains(weekday: weekday)
            else { continue }

            // Hoy no se decide por la secuencia pseudoaleatoria, sino a mano,
            // para que la pantalla Hoy tenga un progreso parcial de verdad.
            if dayKey == endKey {
                if completeToday {
                    let completion = HabitCompletion(
                        dayKey: dayKey,
                        completedAt: calendar.date(fromDayKey: dayKey) ?? end
                    )
                    context.insert(completion)
                    completion.habit = habit
                }
                continue
            }

            // Secuencia pseudoaleatoria reproducible: mismo hábito, mismo día,
            // mismo resultado en cada arranque de la previsualización.
            let pseudo = (offset &* 37 &+ seed &* 101) % 100
            guard pseudo < percent else { continue }

            let completion = HabitCompletion(
                dayKey: dayKey,
                completedAt: calendar.date(fromDayKey: dayKey) ?? end
            )
            context.insert(completion)
            completion.habit = habit
        }
    }
}
