import AppIntents
import Foundation
import SwiftData

// MARK: - Hábito como entidad

/// Un hábito tal y como lo ven Atajos y Siri.
///
/// Es una copia ligera y no el `@Model`: las entidades viajan fuera de la app
/// —a la app Atajos, a Siri— y tienen que poder copiarse sin arrastrar la base.
struct HabitEntity: AppEntity, Identifiable {
    // Calculadas y no `static let`: así no hace falta que estos tipos del
    // framework sean `Sendable` para el modo estricto de Swift 6.
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Hábito" }
    static var defaultQuery: HabitEntityQuery { HabitEntityQuery() }

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

extension HabitEntity {
    init(_ habit: Habit) {
        self.init(id: habit.uuid, name: habit.name)
    }
}

/// Qué hábitos se ofrecen: solo los activos, en el orden del usuario.
///
/// Uno archivado no se puede marcar, así que ofrecerlo en Siri sería ofrecer
/// algo que va a fallar.
struct HabitEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        Self.active(in: CronoPersistence.shared.container.mainContext)
            .filter { identifiers.contains($0.uuid) }
            .map(HabitEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [HabitEntity] {
        Self.matching(string, in: CronoPersistence.shared.container.mainContext)
            .map(HabitEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        Self.active(in: CronoPersistence.shared.container.mainContext)
            .map(HabitEntity.init)
    }

    /// Los hábitos activos. Separado del contexto compartido para poder
    /// probarlo con una base en memoria.
    @MainActor
    static func active(in context: ModelContext) -> [Habit] {
        (try? context.fetch(HabitQueries.active)) ?? []
    }

    /// Los activos cuyo nombre contiene lo dicho, sin distinguir mayúsculas
    /// ni tildes: Siri puede transcribir «meditacion» sin acento.
    @MainActor
    static func matching(_ string: String, in context: ModelContext) -> [Habit] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return active(in: context) }
        return active(in: context).filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

// MARK: - Marcar un hábito

struct MarkHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Marcar hábito"
    static var description: IntentDescription {
        IntentDescription("Marca un hábito de hoy como hecho, o suma uno si se mide en cantidad.")
    }

    @Parameter(title: "Hábito")
    var habit: HabitEntity

    init() {}

    init(habit: HabitEntity) {
        self.habit = habit
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let persistence = CronoPersistence.shared
        let today = Date.now.dayKey
        guard let model = HabitEntityQuery.active(in: persistence.container.mainContext)
            .first(where: { $0.uuid == habit.id })
        else {
            return .result(dialog: "No encuentro ese hábito en Crono.")
        }

        // Desde Siri, «marca Meditar» nunca desmarca: si ya estaba hecho, se
        // dice y no se toca. Desmarcar sin querer por voz no se ve venir.
        if !model.hasQuantityGoal && model.isCompleted(on: today) {
            return .result(dialog: "\(model.name) ya estaba hecho hoy.")
        }

        persistence.habitStore.advance(model, on: today, today: today)
        if let failure = persistence.habitStore.failure {
            persistence.habitStore.failure = nil
            return .result(dialog: "\(failure.message)")
        }

        if model.hasQuantityGoal {
            return .result(dialog: "\(model.name): \(model.progressText(on: today)).")
        }
        return .result(dialog: "Hecho: \(model.name).")
    }
}

// MARK: - Crear una tarea

struct CreateTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Crear tarea"
    static var description: IntentDescription {
        IntentDescription("Añade una tarea a la lista por defecto de Crono.")
    }

    @Parameter(title: "Título")
    var title: String

    @Parameter(title: "Fecha", description: "Si lleva hora, Crono avisará a esa hora.")
    var date: Date?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = CronoPersistence.shared.reminderStore
        guard let list = store.ensureDefaultList() else {
            return .result(dialog: "No he podido abrir la lista de tareas.")
        }

        var dueDay: DayKey?
        var dueMinute: Int?
        if let date {
            dueDay = date.dayKey
            let parts = AppCalendar.current.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            // Una fecha sin hora llega a medianoche; eso no es «avisar a las 0:00».
            dueMinute = minute == 0 ? nil : minute
        }

        guard store.createReminder(title: title, in: list, dueDayKey: dueDay, dueMinuteOfDay: dueMinute) != nil else {
            return .result(dialog: "No he podido guardar la tarea.")
        }
        return .result(dialog: "Añadida a \(list.name): \(title).")
    }
}

// MARK: - Cómo voy hoy

struct TodayProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Progreso de hoy"
    static var description: IntentDescription {
        IntentDescription("Dice cuántos hábitos de hoy llevas hechos.")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let viewModel = TodayViewModel()
        let habits = HabitEntityQuery.active(in: CronoPersistence.shared.container.mainContext)
        let progress = viewModel.progress(for: viewModel.habitsScheduledToday(from: habits))
        return .result(value: progress.completed, dialog: "\(Self.sentence(for: progress))")
    }

    /// La frase que se dice, con el mismo criterio que la pantalla Hoy.
    @MainActor
    static func sentence(for progress: TodayViewModel.DayProgress) -> String {
        if progress.total == 0 { return "Hoy no tienes ningún hábito programado." }
        if progress.isComplete { return "Has hecho los \(progress.total) hábitos de hoy." }
        return "Llevas \(progress.countText) hábitos. Te quedan \(progress.remaining)."
    }
}

// MARK: - Frases

struct CronoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkHabitIntent(),
            phrases: [
                "Marca \(\.$habit) en \(.applicationName)",
                "Marcar \(\.$habit) en \(.applicationName)",
                "Suma \(\.$habit) en \(.applicationName)"
            ],
            shortTitle: "Marcar hábito",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "Crea una tarea en \(.applicationName)",
                "Añade una tarea a \(.applicationName)"
            ],
            shortTitle: "Crear tarea",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodayProgressIntent(),
            phrases: [
                "¿Cómo voy hoy en \(.applicationName)?",
                "Progreso de hoy en \(.applicationName)"
            ],
            shortTitle: "Progreso de hoy",
            systemImageName: "chart.pie"
        )
    }
}
