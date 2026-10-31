import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Ajustes de la app.
///
/// Va en una hoja tras un botón de la barra, no en una cuarta pestaña: las
/// pestañas son para contenido, y esta pantalla crecerá con los ajustes de la
/// alarma y de las tareas sin necesitar sitio propio en la barra.
struct SettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AlarmStore.self) private var alarmStore
    @Environment(ReminderStore.self) private var reminderStore

    /// La copia lista para compartir. Se prepara al abrir Ajustes.
    @State private var exportFile: BackupFile?
    @State private var showingImporter = false
    /// La copia leída, esperando confirmación antes de sustituir nada.
    @State private var pendingRestore: CronoBackup?
    @State private var backupMessage: BackupMessage?
    @State private var lastAutoBackup: Date?

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                backupSection
                aboutSection
            }
            .navigationTitle(Text("Ajustes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { prepareExport() }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                readBackup(result)
            }
            .confirmationDialog(
                "¿Restaurar esta copia?",
                isPresented: isConfirmingRestore,
                titleVisibility: .visible,
                presenting: pendingRestore
            ) { backup in
                Button("Sustituir mis datos", role: .destructive) { restore(backup) }
                Button("Cancelar", role: .cancel) {}
            } message: { backup in
                Text("Se borrará todo lo que hay ahora en Crono y se pondrá lo de la copia: \(backup.summary).")
            }
            .alert(
                backupMessage?.title ?? "",
                isPresented: isShowingMessage,
                presenting: backupMessage
            ) { _ in
                Button("Entendido", role: .cancel) {}
            } message: { message in
                Text(message.text)
            }
        }
    }

    // MARK: - Copia de seguridad

    // MARK: - Acerca de

    /// La versión y el identificador con que está instalada la app.
    ///
    /// Sirven para saber si la tienda desde la que se instaló ha actualizado de
    /// verdad, y si al firmarla le cambió el identificador: con otro
    /// identificador, iOS la trata como una app distinta y la tienda no la
    /// relaciona con su repositorio.
    private var aboutSection: some View {
        Section {
            LabeledContent("Versión", value: Self.versionText)
            LabeledContent("Identificador") {
                Text(Bundle.main.bundleIdentifier ?? "—")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            Text("Acerca de")
        } footer: {
            Text("Si al actualizar no aparece la versión nueva, compara estos datos con los del repositorio en la tienda.")
        }
    }

    /// «1.0.44 (44)».
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var backupSection: some View {
        Section {
            if let exportFile {
                ShareLink(
                    item: exportFile,
                    preview: SharePreview("Copia de Crono", image: Image(systemName: "archivebox"))
                ) {
                    Label("Exportar copia", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                showingImporter = true
            } label: {
                Label("Restaurar desde archivo", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Copia de seguridad")
        } footer: {
            Text(backupFootnote)
        }
    }

    private var backupFootnote: String {
        var text = "Crono guarda una copia cada día en Archivos › En mi iPhone › Crono › Copias, y conserva las \(AutoBackup.keep) últimas."
        if let lastAutoBackup {
            let when = lastAutoBackup.formatted(.relative(presentation: .named))
            text += " La última es de \(when)."
        }
        return text
    }

    /// Fuera del cuerpo por lo mismo que en `RootView`: un `Binding` con dos
    /// cierres dentro de una cadena de modificadores dispara los «unable to
    /// type-check».
    private var isConfirmingRestore: Binding<Bool> {
        Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        )
    }

    private var isShowingMessage: Binding<Bool> {
        Binding(
            get: { backupMessage != nil },
            set: { if !$0 { backupMessage = nil } }
        )
    }

    private func prepareExport() {
        lastAutoBackup = AutoBackup.latestBackupDate()
        do {
            let data = try BackupService.encode(BackupService.snapshot(of: context))
            exportFile = BackupFile(data: data, name: AutoBackup.fileName(for: .now))
        } catch {
            exportFile = nil
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // Un archivo de iCloud Drive o de otra app solo se puede leer
            // dentro de este permiso.
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingRestore = try BackupService.decode(data)
        } catch {
            backupMessage = BackupMessage(
                title: "No se pudo leer la copia",
                text: error.localizedDescription
            )
        }
    }

    private func restore(_ backup: CronoBackup) {
        Task {
            do {
                try await BackupService.restore(
                    backup,
                    into: context,
                    alarmStore: alarmStore,
                    reminderStore: reminderStore
                )
                backupMessage = BackupMessage(
                    title: "Copia restaurada",
                    text: "Ya tienes \(backup.summary)."
                )
                prepareExport()
            } catch {
                backupMessage = BackupMessage(
                    title: "No se pudo restaurar",
                    text: "Tus datos siguen como estaban. \(error.localizedDescription)"
                )
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                // El estilo segmentado no dibuja la etiqueta, pero VoiceOver sí
                // la lee: sin ella, el control se anunciaría sin decir de qué es.
                Text("Apariencia")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Apariencia")
        } footer: {
            Text(footnote)
        }
    }

    /// El pie explica qué implica cada opción en lugar de repetir el nombre del
    /// ajuste, que ya está arriba.
    private var footnote: String {
        switch appearance {
        case .system:
            "Crono usará el modo claro u oscuro según el ajuste de iOS, incluidos los cambios automáticos al anochecer."
        case .light:
            "Crono se mantendrá en modo claro aunque iOS cambie a oscuro."
        case .dark:
            "Crono se mantendrá en modo oscuro aunque iOS cambie a claro."
        }
    }
}

/// La copia como archivo para compartir: guardarla en Archivos, mandarla por
/// correo, dejarla en iCloud Drive.
struct BackupFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in file.data }
            .suggestedFileName { $0.name }
    }
}

private struct BackupMessage: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

#Preview("Ajustes") {
    let container = PreviewData.container()

    SettingsView()
        .modelContainer(container)
        .environment(PreviewData.alarmStore(for: container))
        .environment(PreviewData.reminderStore(for: container))
}
