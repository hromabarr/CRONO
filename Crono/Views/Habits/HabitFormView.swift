import SwiftData
import SwiftUI

/// Formulario para crear y editar un hábito.
///
/// Las dos operaciones comparten pantalla porque son el mismo formulario con
/// distinto punto de partida. El borrador vive en el ViewModel, así que nada se
/// escribe en la base hasta pulsar Guardar y Cancelar no tiene que deshacer nada.
struct HabitFormView: View {
    @State private var viewModel: HabitFormViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    /// Explícito por dos razones: hay propiedades almacenadas privadas —que
    /// harían privado el inicializador sintetizado— y un `@State` se siembra
    /// con `State(initialValue:)`, no por asignación directa.
    init(viewModel: HabitFormViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                routineSection
                goalSection
                colorSection
                scheduleSection
                if viewModel.isEditing { dangerZone }
            }
            .navigationTitle(viewModel.navigationTitle)
            .habitStoreFailureAlert()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if viewModel.save() { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                }
            }
            .confirmationDialog(
                "¿Eliminar este hábito?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    viewModel.delete()
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                // El diálogo dice exactamente qué se pierde. "¿Estás seguro?"
                // no informa de nada.
                Text("Se borrarán también todos sus registros. Esta acción no se puede deshacer.")
            }
        }
    }

    // MARK: - Secciones

    private var nameSection: some View {
        // Cabeceras explícitas en lugar de `Section("Nombre")`: la forma corta
        // deja al inferidor eligiendo entre las sobrecargas de
        // `LocalizedStringKey` y `StringProtocol` dentro de un `Form` genérico.
        Section {
            TextField("Nombre del hábito", text: $viewModel.name)
                .textInputAutocapitalization(.sentences)

            TextField("Descripción (opcional)", text: $viewModel.notes, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
        } header: {
            Text("Nombre")
        }
    }

    /// Cuánto hay que hacer al día. Con 1 es un hábito de sí o no y la unidad
    /// no hace falta, así que se esconde.
    private var goalSection: some View {
        Section {
            Stepper(value: $viewModel.targetCount, in: 1...Habit.maxTarget) {
                LabeledContent("Cada día", value: goalText)
            }

            if viewModel.targetCount > 1 {
                TextField("Unidad (vasos, páginas, min…)", text: $viewModel.unit)
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Objetivo")
        } footer: {
            Text(goalFooter)
        }
    }

    private var goalText: String {
        guard viewModel.targetCount > 1 else { return "Hecho o no" }
        let unit = viewModel.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? "\(viewModel.targetCount)" : "\(viewModel.targetCount) \(unit)"
    }

    private var goalFooter: String {
        viewModel.targetCount > 1
            ? "Cada toque suma uno. El día cuenta como cumplido al llegar al objetivo."
            : "Sube el número para medir cantidades, como vasos de agua o páginas."
    }

    private var routineSection: some View {
        Section {
            Picker("Momento", selection: $viewModel.routine) {
                ForEach(HabitRoutine.allCases) { routine in
                    Text(routine.title).tag(routine)
                }
            }
        } header: {
            Text("Rutina")
        } footer: {
            Text("Se agrupará en Hoy con los hábitos de ese momento. Puedes ordenar los pasos desde Hábitos.")
        }
    }

    private var colorSection: some View {
        Section {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 8),
                spacing: 12
            ) {
                ForEach(HabitColor.allCases) { color in
                    colorSwatch(color)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Color")
        }
    }

    private func colorSwatch(_ color: HabitColor) -> some View {
        let selected = viewModel.color == color

        return Button {
            viewModel.color = color
        } label: {
            Circle()
                .fill(color.color)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // La selección lleva marca además del anillo: con un solo
                    // anillo de color, quien no distingue tonos no sabría cuál
                    // está elegido.
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    if selected {
                        Circle()
                            .strokeBorder(color.color, lineWidth: 2.5)
                            .padding(-4.5)
                    }
                }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(String(localized: color.displayName))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var scheduleSection: some View {
        Section {
            Toggle(
                "Todos los días",
                isOn: Binding(
                    get: { viewModel.isEveryDay },
                    set: { viewModel.setEveryDay($0) }
                )
            )

            WeekdayPickerView(
                isSelected: { viewModel.isSelected(weekday: $0) },
                onToggle: { viewModel.toggle(weekday: $0) }
            )
            .padding(.vertical, 6)
        } header: {
            Text("Días")
        } footer: {
            // La validación aparece mientras se causa el problema, no al pulsar
            // Guardar y descubrir que el botón estaba desactivado sin motivo
            // visible.
            if let message = viewModel.validationMessage {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Programado: \(viewModel.scheduleSummary)")
            }
        }
    }

    private var dangerZone: some View {
        Section {
            Button("Archivar hábito") {
                viewModel.archive()
                dismiss()
            }

            Button("Eliminar hábito", role: .destructive) {
                showingDeleteConfirmation = true
            }
        } footer: {
            // Se explica la diferencia donde se toma la decisión, no en un
            // ajuste escondido: son dos acciones parecidas con consecuencias
            // muy distintas.
            Text("Archivar lo quita de la lista pero conserva su historial y sus rachas. Eliminar borra también los registros.")
        }
    }
}

#Preview("Nuevo hábito") {
    let container = PreviewData.container()

    HabitFormView(
        viewModel: HabitFormViewModel(
            mode: .create,
            store: PreviewData.store(for: container)
        )
    )
    .modelContainer(container)
}

#Preview("Editar hábito") {
    let container = PreviewData.container()
    let habits = (try? container.mainContext.fetch(FetchDescriptor<Habit>())) ?? []
    let store = PreviewData.store(for: container)

    Group {
        if let habit = habits.first {
            HabitFormView(viewModel: HabitFormViewModel(mode: .edit(habit), store: store))
        } else {
            Text("Sin datos de previsualización")
        }
    }
    .modelContainer(container)
}
