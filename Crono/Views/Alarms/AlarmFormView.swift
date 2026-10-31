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

    @State private var disarmKind: DisarmKind
    /// El código registrado, tal y como se guardará. `nil` mientras no haya.
    @State private var pairedCode: String?
    @State private var disarmHint: String
    @State private var insistence: InsistencePlan
    @State private var showingPairing = false
    @State private var showingPrintable = false

    /// Se captura al abrir el formulario, que es «el momento de añadir la
    /// alarma». No se refresca mientras la pantalla sigue abierta: los
    /// formularios son transitorios, y un reloj vivo aquí solo serviría para
    /// recalcular la sección en cada latido.
    private let now = Date.now

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
            _disarmKind = State(initialValue: .stop)
            _pairedCode = State(initialValue: nil)
            _disarmHint = State(initialValue: "")
            _insistence = State(initialValue: .untilDisarmed)

        case let .edit(alarm):
            let start = calendar.startOfDay(for: .now)
            let date = calendar.date(byAdding: .minute, value: alarm.minuteOfDay, to: start) ?? start
            _time = State(initialValue: date)
            _label = State(initialValue: alarm.label)
            _schedule = State(initialValue: alarm.schedule)
            _snoozeEnabled = State(initialValue: alarm.snoozeEnabled)

            switch alarm.disarmMethod {
            case .stop:
                _disarmKind = State(initialValue: .stop)
                _pairedCode = State(initialValue: nil)
            case .arithmetic:
                _disarmKind = State(initialValue: .arithmetic)
                _pairedCode = State(initialValue: nil)
            case let .scannedCode(value):
                _disarmKind = State(initialValue: .code)
                _pairedCode = State(initialValue: value)
            }
            _disarmHint = State(initialValue: alarm.disarmHint)
            // Una alarma sin insistencia propone «hasta que la desarme», para
            // que elegir un método ya deje algo razonable sin tocar nada más.
            _insistence = State(initialValue: alarm.insistence.isActive ? alarm.insistence : .untilDisarmed)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                sleepSection
                repeatSection
                optionsSection
                disarmSection
                if editingAlarm != nil { dangerSection }
            }
            .navigationTitle(Text(editingAlarm == nil ? "Nueva alarma" : "Editar alarma"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                // El permiso se pide aquí, al abrir el formulario, y no al
                // construir la pestaña: un `.task` en una vista dentro de un
                // `TabView` se ejecuta cuando SwiftUI crea la pestaña, que puede
                // ser antes de que el usuario la vea siquiera. Se pedía sin que
                // nadie hubiera ido a Alarmas, y el diálogo aparecía encima de
                // otras pantallas.
                //
                // Tocar «+» sí es intención inequívoca, y es antes de que el
                // usuario haya invertido tiempo rellenando nada.
                if store.authorization == .notDetermined {
                    await store.requestAuthorization()
                }
            }
            .sheet(isPresented: $showingPairing) {
                DisarmCodePairingView { pairedCode = $0 }
            }
            .sheet(isPresented: $showingPrintable) {
                if let pairedCode {
                    PrintableCodeView(value: pairedCode, hint: disarmHint)
                }
            }
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

    /// A qué hora acostarse para llegar a la alarma con ciclos completos.
    ///
    /// Va justo debajo del selector de hora porque depende de él: al girar la
    /// rueda, las horas sugeridas se mueven con ella.
    private var sleepSection: some View {
        SleepCycleSection(
            wakeMinuteOfDay: AlarmStore.minuteOfDay(of: time),
            now: now
        )
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

    /// Qué hay que hacer para que la alarma deje de volver.
    private var disarmSection: some View {
        Section {
            Picker("Para que no vuelva", selection: $disarmKind) {
                ForEach(DisarmKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }

            if disarmKind == .code { codeRows }

            if disarmKind != .stop {
                Toggle("Hasta que la desarme", isOn: untilDisarmed)

                if !insistence.isUntilDisarmed {
                    Stepper(value: $insistence.intervalMinutes, in: 1...10) {
                        LabeledContent("Vuelve cada", value: "\(insistence.intervalMinutes) min")
                    }
                    Stepper(value: $insistence.repeats, in: 1...10) {
                        LabeledContent("Veces", value: "\(insistence.repeats)")
                    }
                }
            }
        } header: {
            Text("Desarme")
        } footer: {
            Text(disarmFooter)
        }
    }

    @ViewBuilder
    private var codeRows: some View {
        if let pairedCode {
            LabeledContent("Código") {
                Text(pairedCode)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // La pista es lo que se verá a las siete de la mañana. Sin ella no
            // te acuerdas de qué registraste hace tres semanas.
            TextField("Dónde está (p. ej. el bote de champú)", text: $disarmHint)
                .textInputAutocapitalization(.never)
            Button("Escanear otro código") { showingPairing = true }
            Button("Ver como QR para imprimir") { showingPrintable = true }
        } else {
            Button("Escanear un código") { showingPairing = true }
            Button("Crear un QR para imprimir") {
                pairedCode = DisarmCode.makeSecret()
                disarmHint = ""
                showingPrintable = true
            }
        }
    }

    /// El interruptor elige entre el plan sin descanso y uno a medida.
    ///
    /// Sale del cuerpo de la vista por lo mismo que el de la alerta en
    /// `RootView`: un `Binding` con dos cierres dentro de una cadena de
    /// modificadores es lo que dispara los «unable to type-check».
    private var untilDisarmed: Binding<Bool> {
        Binding(
            get: { insistence.isUntilDisarmed },
            set: { insistence = $0 ? .untilDisarmed : .default }
        )
    }

    private var disarmFooter: String {
        guard disarmKind != .stop else { return DisarmMethod.stop.explanation }
        if disarmKind == .code, pairedCode == nil {
            return "Registra un código para poder guardar la alarma."
        }
        if insistence.isUntilDisarmed {
            // Se dice lo que de verdad pasa: iOS deja parar cualquier alarma,
            // y prometer otra cosa sería mentir justo en lo que importa.
            let task = disarmKind == .code ? "escanees tu código" : "resuelvas la cuenta"
            return "Podrás pararla, pero volverá cada minuto hasta que \(task), durante una hora como máximo. Mientras suene no se podrá cambiar ni apagar."
        }
        let span = InsistenceCalculator.totalSpanMinutes(insistence)
        return "\(disarmMethod.explanation) Te insistirá durante \(span) minutos. Mientras suene no se podrá cambiar ni apagar."
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
                .disabled(schedule.isEmpty || (disarmKind == .code && pairedCode == nil))
        }
    }

    // MARK: - Acciones

    private var editingAlarm: AlarmItem? {
        if case let .edit(alarm) = mode { return alarm }
        return nil
    }

    private var disarmMethod: DisarmMethod {
        switch disarmKind {
        case .stop: .stop
        case .arithmetic: .arithmetic
        case .code: pairedCode.flatMap(DisarmCode.method(for:)) ?? .stop
        }
    }

    private func save() {
        let minute = AlarmStore.minuteOfDay(of: time)
        let editing = editingAlarm
        let currentLabel = label
        let currentSchedule = schedule
        let currentSnooze = snoozeEnabled
        let currentMethod = disarmMethod
        let currentHint = disarmHint
        let currentInsistence = insistence

        Task {
            if let editing {
                await store.update(
                    editing,
                    minuteOfDay: minute,
                    label: currentLabel,
                    schedule: currentSchedule,
                    snoozeEnabled: currentSnooze,
                    disarmMethod: currentMethod,
                    disarmHint: currentHint,
                    insistence: currentInsistence
                )
            } else {
                await store.create(
                    minuteOfDay: minute,
                    label: currentLabel,
                    schedule: currentSchedule,
                    snoozeEnabled: currentSnooze,
                    disarmMethod: currentMethod,
                    disarmHint: currentHint,
                    insistence: currentInsistence
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

/// Lo que elige el usuario en el selector de desarme.
///
/// No es `DisarmMethod` porque el código no se conoce al elegir: primero se
/// elige «escanear» y luego se registra qué. Un `DisarmMethod` sin código no
/// existe, a propósito.
private enum DisarmKind: Hashable, CaseIterable {
    case stop
    case arithmetic
    case code

    var label: String {
        switch self {
        case .stop: DisarmMethod.stop.label
        case .arithmetic: DisarmMethod.arithmetic.label
        case .code: DisarmMethod.scannedCode(value: "").label
        }
    }
}

#Preview("Nueva alarma") {
    let container = PreviewData.container()

    AlarmFormView(mode: .create)
        .environment(PreviewData.alarmStore(for: container))
        .modelContainer(container)
}
