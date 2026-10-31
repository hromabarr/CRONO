import SwiftUI
import UIKit

/// La pantalla que cancela las vueltas de esta mañana.
///
/// Aparece sola al abrir la app mientras una alarma insiste. Se puede cerrar con
/// «Ahora no», y no pasa nada: cerrarla no desarma, así que la alarma vuelve y
/// la pantalla con ella. Lo que no hay es otra forma de que deje de volver.
struct DisarmView: View {
    let alarm: AlarmItem

    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(alarm.timeText)
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(alarm.displayLabel)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                switch alarm.disarmMethod {
                case .arithmetic:
                    ArithmeticDisarmView(onSolved: disarm)
                case let .scannedCode(expected):
                    CodeDisarmView(expected: expected, hint: alarm.disarmHint, onMatched: disarm)
                case .stop:
                    // No debería llegar aquí: una alarma sin método no espera
                    // desarme. Si llega, se deja salir.
                    Button("Cerrar", action: disarm)
                        .buttonStyle(.borderedProminent)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(Text("Desarmar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ahora no") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func disarm() {
        let alarm = alarm
        Task {
            await store.disarm(alarm)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

// MARK: - Cuenta

private struct ArithmeticDisarmView: View {
    let onSolved: () -> Void

    @State private var challenge = ArithmeticChallenge.make()
    @State private var input = ""
    @State private var failedOnce = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(challenge.question)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel(Text("Resuelve: \(challenge.question)"))

            TextField("Resultado", text: $input)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .focused($isFocused)

            if failedOnce {
                Text("No es correcto. Prueba con esta.")
                    .foregroundStyle(.red)
            }

            Button("Comprobar", action: check)
                .buttonStyle(.borderedProminent)
                .disabled(input.isEmpty)
        }
        .onAppear { isFocused = true }
    }

    private func check() {
        if challenge.accepts(input) {
            onSolved()
        } else {
            // Una cuenta nueva y no un segundo intento con la misma: si no,
            // basta con ir probando números.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            challenge = ArithmeticChallenge.make()
            input = ""
            failedOnce = true
        }
    }
}

// MARK: - Código

private struct CodeDisarmView: View {
    let expected: String
    let hint: String
    let onMatched: () -> Void

    private let scanner = CameraCodeScanner()

    @State private var cameraReady: Bool?
    @State private var isTorchOn = false
    @State private var attempt = 0
    @State private var rejected = false
    @State private var typed = ""

    private var method: DisarmMethod { .scannedCode(value: expected) }

    var body: some View {
        VStack(spacing: 16) {
            Text(hintText)
                .font(.headline)
                .multilineTextAlignment(.center)

            camera
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(.rect(cornerRadius: 20))

            if rejected {
                Text("Ese no es el código.")
                    .foregroundStyle(.red)
            }

            // Por si la cámara falla. Teclear un código de barras o el secreto
            // impreso cuesta lo mismo que ir a escanearlo: hay que ir hasta él.
            DisclosureGroup("Escribirlo a mano") {
                HStack {
                    TextField("Código", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("Comprobar") { check(typed) }
                        .disabled(typed.isEmpty)
                }
                .padding(.top, 8)
            }
        }
        .task {
            if scanner.isAvailable {
                cameraReady = await scanner.requestAuthorization()
            } else {
                cameraReady = false
            }
        }
    }

    private var hintText: String {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Escanea tu código" : "Escanea: \(trimmed)"
    }

    @ViewBuilder
    private var camera: some View {
        switch cameraReady {
        case nil:
            ProgressView()
        case false?:
            ContentUnavailableView(
                "Sin cámara",
                systemImage: "camera",
                description: Text("Escribe el código a mano.")
            )
        case true?:
            CodeScannerView(isTorchOn: isTorchOn) { check($0.value) }
                .id(attempt)
                .overlay(alignment: .topTrailing) {
                    if scanner.hasTorch {
                        Button {
                            isTorchOn.toggle()
                        } label: {
                            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .padding(10)
                                .background(.regularMaterial, in: .circle)
                        }
                        .accessibilityLabel(Text(isTorchOn ? "Apagar linterna" : "Encender linterna"))
                        .padding(8)
                    }
                }
        }
    }

    private func check(_ value: String) {
        if DisarmCode.matches(value, method: method) {
            onMatched()
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.error)
        rejected = true
        // El lector entrega un código y se calla. Se espera un momento antes de
        // crear otro: si no, el mismo código equivocado, que sigue delante de
        // la cámara, se volvería a leer al instante una y otra vez.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            attempt += 1
        }
    }
}
