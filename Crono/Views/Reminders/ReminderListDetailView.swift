import SwiftData
import SwiftUI

/// Las tareas de una lista, con las completadas al final.
struct ReminderListDetailView: View {
    private let list: ReminderList

    @Environment(ReminderStore.self) private var store

    @State private var quickTitle = ""
    @State private var showingCompleted = false

    /// Una sola hoja para crear y para editar. Dos `@State` booleanos separados
    /// se pisan entre sí cuando el usuario toca rápido.
    @State private var formMode: ReminderFormView.Mode?

    init(list: ReminderList) {
        self.list = list
    }

    var body: some View {
        List {
            pendingSection
            if !completed.isEmpty { completedSection }
        }
        .navigationTitle(Text(list.name))
        .toolbar { toolbarContent }
        .sheet(item: $formMode) { mode in
            ReminderFormView(mode: mode)
        }
    }

    // MARK: - Secciones

    @ViewBuilder
    private var pendingSection: some View {
        Section {
            ForEach(pending) { reminder in
                row(reminder)
            }
            .onMove { source, destination in
                store.moveReminders(pending, from: source, to: destination)
            }

            quickAddField
        } footer: {
            if pending.isEmpty {
                Text("Escribe arriba para añadir tu primera tarea a esta lista.")
            }
        }
    }

    private var completedSection: some View {
        Section {
            if showingCompleted {
                ForEach(completed) { reminder in
                    row(reminder)
                }
            }
        } header: {
            HStack {
                Text("Completadas: \(completed.count)")
                Spacer()
                Button(showingCompleted ? "Ocultar" : "Mostrar") {
                    showingCompleted.toggle()
                }
                .font(.footnote.weight(.semibold))
                .textCase(nil)
            }
        }
    }

    /// Campo para añadir sin abrir el formulario.
    ///
    /// Es la vía rápida que hace usable una app de tareas: la mayoría de veces
    /// solo hay un título que apuntar antes de que se olvide. La fecha, la
    /// prioridad y el resto se añaden después, tocando la tarea.
    private var quickAddField: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(list.color.color)

            TextField("Nueva tarea", text: $quickTitle)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addQuickReminder)
        }
        .padding(.vertical, 2)
    }

    private func row(_ reminder: Reminder) -> some View {
        Button {
            formMode = .edit(reminder)
        } label: {
            ReminderRowView(
                reminder: reminder,
                tint: list.color.color,
                today: today,
                nowMinuteOfDay: nowMinuteOfDay,
                onToggle: { store.toggleCompletion(for: reminder) }
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.delete(reminder)
            } label: {
                Label(text: "Eliminar", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                toggleFlag(reminder)
            } label: {
                Label(text: reminder.isFlagged ? "Quitar" : "Bandera", systemImage: "flag")
            }
            .tint(.orange)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !completed.isEmpty {
                Button("Borrar hechas") {
                    store.clearCompleted(in: list)
                }
            }

            Button {
                formMode = .create(list)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("Nueva tarea con detalles")
        }
    }

    // MARK: - Datos

    /// Se ordenan y filtran en Swift sobre la relación ya cargada.
    ///
    /// La lista trae sus tareas por la relación, así que no hace falta una
    /// consulta aparte con un predicado sobre `list`, que es justo el tipo de
    /// predicado sobre relaciones que este proyecto evita.
    private var pending: [Reminder] {
        var result: [Reminder] = []
        for reminder in list.reminders where !reminder.isCompleted && reminder.parent == nil {
            result.append(reminder)
        }
        return result.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var completed: [Reminder] {
        var result: [Reminder] = []
        for reminder in list.reminders where reminder.isCompleted && reminder.parent == nil {
            result.append(reminder)
        }
        return result.sorted { lhs, rhs in
            (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
        }
    }

    private var today: DayKey { Date.now.dayKey }
    private var nowMinuteOfDay: Int { SmartReminderListView.currentMinuteOfDay() }

    // MARK: - Acciones

    private func addQuickReminder() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        quickTitle = ""
        guard !title.isEmpty else { return }
        store.createReminder(title: title, in: list)
    }

    private func toggleFlag(_ reminder: Reminder) {
        store.update(
            reminder,
            title: reminder.title,
            notes: reminder.notes,
            dueDayKey: reminder.dueDayKey,
            dueMinuteOfDay: reminder.dueMinuteOfDay,
            priority: reminder.priority,
            isFlagged: !reminder.isFlagged,
            recurrence: reminder.recurrence,
            list: nil
        )
    }
}

#Preview("Lista") {
    let container = PreviewData.container()
    let lists = (try? container.mainContext.fetch(FetchDescriptor<ReminderList>())) ?? []

    NavigationStack {
        if let list = lists.first {
            ReminderListDetailView(list: list)
        } else {
            Text("Sin datos de previsualización")
        }
    }
    .modelContainer(container)
    .environment(PreviewData.reminderStore(for: container))
}
