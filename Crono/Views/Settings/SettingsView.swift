import SwiftUI

/// Ajustes de la app.
///
/// Va en una hoja tras un botón de la barra, no en una cuarta pestaña: las
/// pestañas son para contenido, y esta pantalla crecerá con los ajustes de la
/// alarma y de las tareas sin necesitar sitio propio en la barra.
struct SettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
            }
            .navigationTitle(Text("Ajustes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .fontWeight(.semibold)
                }
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

#Preview("Ajustes") {
    SettingsView()
}
