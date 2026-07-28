import SwiftData
import SwiftUI

/// Raíz de la pestaña Alarmas.
struct AlarmListView: View {
    @Query(AlarmQueries.all) private var alarms: [AlarmItem]

    @Environment(AlarmStore.self) private var store

    @State private var formMode: AlarmFormView.Mode?

    init() {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Alarmas"))
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .sheet(item: $formMode) { mode in
                    AlarmFormView(mode: mode)
                }
        }
        .task {
            // Se pide al abrir la pestaña, no al arrancar la app: pedir permisos
            // antes de que el usuario haya mostrado interés es la forma más
            // rápida de que los deniegue.
            if store.authorization == .notDetermined {
                await store.requestAuthorization()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if alarms.isEmpty {
            EmptyStateView(
                title: "Sin alarmas",
                message: "Crea una alarma y Crono te despertará a la hora que le digas, aunque el móvil esté en silencio.",
                systemImage: "alarm",
                actionTitle: "Crear alarma",
                action: { formMode = .create }
            )
        } else {
            List {
                if let notice = authorizationNotice {
                    Section { AuthorizationNoticeRow(message: notice) }
                }

                Section {
                    ForEach(alarms) { alarm in
                        row(alarm)
                    }
                    .onDelete { offsets in
                        delete(at: offsets)
                    }
                }
            }
        }
    }

    private func row(_ alarm: AlarmItem) -> some View {
        AlarmRowView(
            alarm: alarm,
            isRegistered: alarm.systemAlarmID != nil,
            onEdit: { formMode = .edit(alarm) },
            onToggle: { isOn in
                Task { await store.setEnabled(isOn, for: alarm) }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { formMode = .create } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Nueva alarma")
        }
    }

    /// Explica por qué una alarma guardada podría no sonar.
    ///
    /// Guardar una alarma que el sistema no va a disparar y no decirlo es la peor
    /// combinación posible en un despertador: el usuario se acuesta creyendo que
    /// está puesta.
    private var authorizationNotice: String? {
        switch store.authorization {
        case .authorized:
            return nil
        case .denied:
            return "Crono no tiene permiso para poner alarmas, así que estas no van a sonar. Puedes concederlo en Ajustes de iOS."
        case .notDetermined:
            return "Falta conceder el permiso de alarmas. Hasta entonces, estas no sonarán."
        case .unavailable:
            return "Este dispositivo no permite que Crono ponga alarmas del sistema. Se guardan, pero no sonarán."
        }
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.compactMap { alarms.indices.contains($0) ? alarms[$0] : nil }
        Task {
            for alarm in doomed {
                await store.delete(alarm)
            }
        }
    }
}

// MARK: - Filas

private struct AuthorizationNoticeRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct AlarmRowView: View {
    let alarm: AlarmItem
    let isRegistered: Bool
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alarm.timeText)
                        // Grande y con cifras de ancho fijo: es el dato que se
                        // busca de un vistazo, y sin `monospacedDigit` la hora
                        // baila al cambiar de dígito.
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(alarm.isEnabled ? .primary : .secondary)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Toca la hora para editar")
        .accessibilityAction(named: alarm.isEnabled ? "Desactivar" : "Activar") {
            onToggle(!alarm.isEnabled)
        }
    }

    private var subtitle: String {
        var parts = [alarm.displayLabel, alarm.scheduleText]
        // Se dice cuando una alarma activa no llegó a registrarse en el sistema.
        if alarm.isEnabled && !isRegistered && !alarm.schedule.isEmpty {
            parts.append("no registrada")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let state = alarm.isEnabled ? "activada" : "desactivada"
        return "\(alarm.timeText), \(alarm.displayLabel), \(alarm.scheduleText), \(state)"
    }
}

#Preview("Alarmas") {
    let container = PreviewData.container()

    AlarmListView()
        .modelContainer(container)
        .environment(PreviewData.alarmStore(for: container))
}
