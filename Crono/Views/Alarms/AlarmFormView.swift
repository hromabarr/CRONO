import SwiftUI

/// Formulario para crear y editar una alarma.
struct AlarmFormView: View {
    enum Mode: Identifiable {
        case create
        case edit(AlarmItem)

        var id: String {
            switch self {
            case .create: "create"
            case let .edit(alarm): "edit-\(alarm.uuid.uuidString)"
            }
        }
    }

    private let mode: Mode

    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var time: Date
    @State private var label: String
    @State private var schedule: WeekdaySet
    @State private var snoozeEnabled: Bool
    @State private var showingDeleteConfirmation = false

    init(mode: Mode) {
        self.mode = mode

        let calendar = AppCalendar.current
        switch mode {
        case .create:
            // Las 7:00 por defecto: es una alarma de despertador, y un valor
            // razonable ahorra al usuario girar la rueda desde medianoche.
            let start = calendar.startOfDay(for: .now)
            _time = State(initialValue: calendar.date(byAdding: .hour, value: 7, to: start) ?? start)
            _label = State(initialValue: "")
            _schedule = State(initialValue: .everyDay)
            _snoozeEnabled = State(initialValue: true)

        case let .edit(alarm):
            let start = calendar.startOfDay(for: .now)
            let date = calendar.date(byAdding: .minute, value: alarm.minuteOfDay, to: start) ?? start
            _time = State(initialValue: date)
            _label = State(initialValue: alarm.label)
            _schedule = State(initialValue: alarm.schedule)
            _snoozeEnabled = State(initialValue: alarm.snoozeEnabled)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                repeatSection
                optionsSection
                if editingAlarm != nil { dangerSection }
            }
            .navigationTitle(Text(editingAlarm == nil ? "Nueva alarma" : "Editar alarma"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog(
                "¿Eliminar esta alarma?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) { delete() }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    // MARK: - Secciones

    private var timeSection: some View {
        Section {
            DatePicker(
                selection: $time,
                displayedComponents: [.hourAndMinute]
            ) {
                Text("Hora")
            }
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private var repeatSection: some View {
        Section {
            WeekdayPickerView(
                isSelected: { schedule.contains(weekday: $0) },
                onToggle: { schedule = schedule.toggling(weekday: $0) }
            )
            .padding(.vertical, 6)
        } header: {
            Text("Repetir")
        } footer: {
            // Sin días la alarma no suena nunca, y eso hay que decirlo aquí y no
            // dejar que el usuario lo descubra a la mañana siguiente.
            if schedule.isEmpty {
                Text("Elige al menos un día. Sin días, la alarma no sonará.")
                    .foregroundStyle(.red)
            } else {
                Text(schedule.displayDescription)
            }
        }
    }

    private var optionsSection: some View {
        Section {
            TextField("Etiqueta", text: $label)
                .textInputAutocapitalization(.sentences)

            Toggle("Posponer", isOn: $snoozeEnabled)
        } footer: {
            Text("Con Posponer activado, la alerta ofrece un botón para volver a sonar más tarde.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Eliminar alarma", role: .destructive) {
                showingDeleteConfirmation = true
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Guardar") { save() }
                .fontWeight(.semibold)
                .disabled(schedule.isEmpty)
        }
    }

    // MARK: - Acciones

    private var editingAlarm: AlarmItem? {
        if case let .edit(alarm) = mode { return alarm }
        return nil
    }

    private func save() {
        let minute = AlarmStore.minuteOfDay(of: time)
        let editing = editingAlarm
        let currentLabel = label
        let currentSchedule = schedule
        let currentSnooze = snoozeEnabled

        Task {
            if let editing {
                await store.update(
                    editing,
                    minuteOfDay: minute,
                    label: currentLabel,
                    schedule: currentSchedule,
                    snoozeEnabled: currentSnooze
                )
            } else {
                await store.create(
                    minuteOfDay: minute,
                    label: currentLabel,
                    schedule: currentSchedule,
                    snoozeEnabled: currentSnooze
                )
            }
        }
        dismiss()
    }

    private func delete() {
        guard let editing = editingAlarm else { return }
        Task { await store.delete(editing) }
        dismiss()
    }
}

#Preview("Nueva alarma") {
    let container = PreviewData.container()

    AlarmFormView(mode: .create)
        .environment(PreviewData.alarmStore(for: container))
        .modelContainer(container)
}
