import SwiftUI

/// Hoja para registrar el código que desarmará una alarma.
///
/// Lee un código y lo enseña antes de guardarlo. Ese paso intermedio importa: la
/// cámara lee lo primero que encuentra, y si al apuntar al bote de champú
/// asomaba la caja de al lado, el usuario tiene que poder verlo ahora y no a
/// las siete de la mañana.
struct DisarmCodePairingView: View {
    let onPair: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let scanner: CameraCodeScanner

    @State private var phase: Phase = .checking
    @State private var isTorchOn = false
    /// Cambiarlo crea un lector nuevo, que vuelve a aceptar un código.
    @State private var attempt = 0

    private enum Phase: Equatable {
        case checking
        case scanning
        case scanned(ScannedCode)
        case denied
        case unavailable
    }

    init(scanner: CameraCodeScanner = CameraCodeScanner(), onPair: @escaping (String) -> Void) {
        self.scanner = scanner
        self.onPair = onPair
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Registrar código"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .task { await prepare() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .checking:
            ProgressView()

        case .scanning:
            scanningView

        case let .scanned(code):
            scannedView(code)

        case .denied:
            ContentUnavailableView {
                Label("Sin acceso a la cámara", systemImage: "camera.badge.ellipsis")
            } description: {
                Text("Crono necesita la cámara para leer el código. Puedes permitirlo en Ajustes.")
            } actions: {
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }

        case .unavailable:
            ContentUnavailableView(
                "No hay cámara",
                systemImage: "camera",
                description: Text("Este aparato no tiene una cámara con la que leer códigos.")
            )
        }
    }

    private var scanningView: some View {
        CodeScannerView(isTorchOn: isTorchOn) { code in
            withAnimation { phase = .scanned(code) }
        }
        .id(attempt)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            Text("Apunta a un QR o al código de barras de algo que esté lejos de la cama.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .padding()
        }
        .accessibilityLabel(Text("Imagen de la cámara"))
    }

    private func scannedView(_ code: ScannedCode) -> some View {
        Form {
            Section {
                Text(code.value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(4)
            } header: {
                Text("Código leído")
            } footer: {
                Text("La alarma solo dejará de volver al escanear exactamente este código.")
            }

            Section {
                Button("Usar este código") {
                    onPair(code.value)
                    dismiss()
                }
                .fontWeight(.semibold)

                Button("Volver a escanear") {
                    attempt += 1
                    withAnimation { phase = .scanning }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancelar") { dismiss() }
        }
        if phase == .scanning, scanner.hasTorch {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isTorchOn.toggle()
                } label: {
                    Label(
                        isTorchOn ? "Apagar linterna" : "Encender linterna",
                        systemImage: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
                    )
                }
            }
        }
    }

    private func prepare() async {
        guard scanner.isAvailable else {
            phase = .unavailable
            return
        }
        if await scanner.requestAuthorization() {
            phase = .scanning
        } else {
            phase = .denied
        }
    }
}
