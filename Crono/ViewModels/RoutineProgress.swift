import Foundation

/// A routine resumes from saved daily completions, not a separate step index.
struct RoutineProgress {
    let habits: [Habit]
    let day: DayKey

    init(routine: HabitRoutine, habits: [Habit], day: DayKey) {
        self.day = day
        self.habits = habits
            .filter { $0.isActive && $0.routine == routine && $0.isScheduled(on: day) }
            // El orden tiene que ser total, no solo bueno la mayoría de las
            // veces. `sorted` no garantiza estabilidad y el `fetch` de SwiftData
            // no promete un orden, así que dos hábitos empatados salían en un
            // orden u otro entre arranques: la rutina decía «Siguiente: Correr»
            // una vez y «Siguiente: Agua» la siguiente, sin que nada cambiara.
            //
            // Empatar en `sortIndex` es fácil: el valor por defecto es 0 y
            // cualquier hábito creado sin pasarlo se queda ahí.
            .sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                // Alfabético antes que el identificador: un empate resuelto por
                // nombre parece intencionado, y uno resuelto por UUID parece
                // averiado, aunque los dos sean igual de estables.
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.uuid.uuidString < $1.uuid.uuidString
            }
    }

    var next: Habit? { habits.first { !$0.isCompleted(on: day) } }
    var completedCount: Int { habits.filter { $0.isCompleted(on: day) }.count }

    var actionTitle: String {
        if next == nil { return "Revisar rutina" }
        return completedCount == 0 ? "Empezar rutina" : "Continuar rutina"
    }
}
