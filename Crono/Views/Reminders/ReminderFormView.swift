import SwiftData
import SwiftUI

/// Formulario para crear y editar una tarea.
struct ReminderFormView: View {
    /// Modo de presentación. Solo `Identifiable`, que es lo que pide
    /// `.sheet(item:)` — y así el contexto viaja dentro en lugar de necesitar un
    /// booleano aparte.
    ///
    /// No se declara `Hashable`: los casos llevan clases `@Model` dentro y su
    /// conformidad a `Hashable` no está garantizada.
    enum Mode: Identifiable {
        case create(ReminderList)
        case edit(Reminder)

        var id: String {
            switch self {
            case let .create(list): "create-\(list.uuid.uuidString)"
            case let .edit(reminder): "edit-\(reminder.uuid.uuidString)"
            }
        }
    }

    private let mode: Mode

    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ReminderFormViewModel?
    @State private var showingDeleteConfirmation = false

    init(mode: Mode) {
        self.mode = mode
    }

    var body: some View {
        NavigationStack {
            container
                .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if viewModel == nil {
                viewModel = ReminderFormViewModel(store: store, mode: viewModelMode)
            }
        }
    }

    @ViewBuilder
    private var container: some View {
        if let viewModel {
            ReminderFormContent(
                viewModel: viewModel,
                onCancel: { dismiss() },
                onSave: { if viewModel.save() { dismiss() } },
                onDelete: { showingDeleteConfirmation = true }
            )
            .navigationTitle(Text(viewModel.navigationTitle))
            .confirmationDialog(
                "¿Eliminar esta tarea?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    viewModel.delete()
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrarán también sus subtareas. Esta acción no se puede deshacer.")
            }
        } else {
            Color(uiColor: .systemGroupedBackground)
        }
    }

    private var viewModelMode: ReminderFormViewModel.Mode {
        switch mode {
        case let .create(list): .create(list)
        case let .edit(reminder): .edit(reminder)
        }
    }
}

// MARK: - Contenido

private struct ReminderFormContent: View {
    @Bindable var viewModel: ReminderFormViewModel

    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Form {
            titleSection
            dueSection
            markersSection
            if viewModel.isEditing { dangerSection }
        }
        .toolbar { toolbarContent }
    }

    private var titleSection: some View {
        Section {
            TextField("Título", text: $viewModel.title)
                .textInputAutocapitalization(.sentences)

            TextField("Notas", text: $viewModel.notes, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
        } header: {
            Text("Tarea")
        } footer: {
            Text("En \(viewModel.listName)")
        }
    }

    @ViewBuilder
    private var dueSection: some View {
        Section {
            Toggle("Fecha", isOn: $viewModel.hasDueDate)

            if viewModel.hasDueDate {
                DatePicker(
                    selection: $viewModel.dueDate,
                    displayedComponents: viewModel.hasDueTime ? [.date, .hourAndMinute] : [.date]
                ) {
                    Text("Vence")
                }

                Toggle("Hora", isOn: $viewModel.hasDueTime)

                Toggle("Repetir", isOn: $viewModel.repeats)

                if viewModel.repeats {
                    Picker(selection: $viewModel.recurrence) {
                        Text("Cada día").tag(RecurrenceRule.daily)
                        Text("Días laborables").tag(RecurrenceRule.weekly(.weekdays))
                        Text("Cada semana").tag(RecurrenceRule.weekly(.everyDay))
                        Text("Cada mes").tag(RecurrenceRule.monthly)
                        Text("Cada año").tag(RecurrenceRule.yearly)
                    } label: {
                        Text("Frecuencia")
                    }
                }
            }
        } header: {
            Text("Vencimiento")
        } footer: {
            // Sin hora no hay aviso: hay que decirlo donde se decide, no
            // dejar al usuario preguntándose por qué no le sonó nada.
            if let message = viewModel.validationMessage {
                Text(message).foregroundStyle(.red)
            } else if viewModel.hasDueDate && !viewModel.hasDueTime {
                Text("Sin hora, la tarea aparece en su día pero no te avisa.")
            } else if viewModel.hasDueTime {
                Text("Recibirás un aviso a esa hora.")
            }
        }
    }

    private var markersSection: some View {
        Section {
            Picker(selection: $viewModel.priority) {
                ForEach(ReminderPriority.allCases) { level in
                    Text(level.label).tag(level)
                }
            } label: {
                Text("Prioridad")
            }

            Toggle("Bandera", isOn: $viewModel.isFlagged)
        } header: {
            Text("Marcas")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Eliminar tarea", role: .destructive, action: onDelete)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancelar", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Guardar", action: onSave)
                .fontWeight(.semibold)
                .disabled(!viewModel.canSave)
        }
    }
}

#Preview("Nueva tarea") {
    let container = PreviewData.container()
    let lists = (try? container.mainContext.fetch(FetchDescriptor<ReminderList>())) ?? []

    Group {
        if let list = lists.first {
            ReminderFormView(mode: .create(list))
        } else {
            Text("Sin datos de previsualización")
        }
    }
    .modelContainer(container)
    .environment(PreviewData.reminderStore(for: container))
}
