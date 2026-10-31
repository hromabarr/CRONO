@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Lo que ve la cámara trasera, avisando del primer código que lea.
///
/// Entrega **un** código y se calla: el lector ve el mismo código treinta veces
/// por segundo, y sin ese freno la hoja de emparejado recibiría una ráfaga. Para
/// leer otro se crea una vista nueva (`.id(_:)`), que es más difícil de
/// equivocar que un estado que haya que acordarse de reiniciar.
struct CodeScannerView: UIViewRepresentable {
    var isTorchOn: Bool
    let onScan: (ScannedCode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.configure(delegate: context.coordinator)
        view.start()
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        context.coordinator.onScan = onScan
        view.setTorch(isTorchOn)
    }

    static func dismantleUIView(_ view: CameraPreviewView, coordinator: Coordinator) {
        // La linterna no se apaga sola al cerrar la sesión en todos los
        // aparatos, y quedarse con ella encendida en el bolsillo es lo último
        // que se espera de una pantalla de ajustes.
        view.setTorch(false)
        view.stop()
    }

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: (ScannedCode) -> Void
        private var delivered = false

        init(onScan: @escaping (ScannedCode) -> Void) {
            self.onScan = onScan
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = code.stringValue
            else { return }
            let scanned = ScannedCode(value: value, symbology: code.type.rawValue)

            // El delegado se registra en la cola principal (ver
            // `CameraPreviewView.configure`), así que esto ya corre en ella.
            MainActor.assumeIsolated { self.deliver(scanned) }
        }

        private func deliver(_ code: ScannedCode) {
            guard !delivered, DisarmCode.isUsable(code.value) else { return }
            delivered = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onScan(code)
        }
    }
}

/// La vista de UIKit cuya capa es la imagen de la cámara.
final class CameraPreviewView: UIView {
    /// Los formatos que se aceptan: todo lo que la cámara sepa leer, porque el
    /// emparejado va por el contenido y no por el formato. Un código de barras
    /// de un bote vale igual que un QR impreso.
    private static let symbologies: [AVMetadataObject.ObjectType] = [
        .qr, .microQR, .dataMatrix, .aztec, .pdf417,
        .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .interleaved2of5
    ]

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    // `layerClass` garantiza el tipo: UIKit crea la capa a partir de él.
    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    private let runner = CaptureSessionRunner()
    private var device: AVCaptureDevice?

    func configure(delegate: some AVCaptureMetadataOutputObjectsDelegate) {
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = runner.session

        guard let camera = CameraCodeScanner.camera,
              let input = try? AVCaptureDeviceInput(device: camera)
        else { return }

        let session = runner.session
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        output.setMetadataObjectsDelegate(delegate, queue: .main)
        // Pedir un tipo que el aparato no admite lanza una excepción de
        // Objective-C, no un error de Swift; por eso se filtra antes.
        let available = output.availableMetadataObjectTypes
        output.metadataObjectTypes = Self.symbologies.filter { available.contains($0) }

        device = camera
    }

    func start() { runner.start() }

    func stop() { runner.stop() }

    func setTorch(_ isOn: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        let mode: AVCaptureDevice.TorchMode = isOn ? .on : .off
        guard device.torchMode != mode else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {
            // Sin linterna se sigue pudiendo leer con luz; no merece un aviso.
        }
    }
}

/// Arranca y para la sesión fuera del hilo principal.
///
/// `startRunning()` bloquea hasta que la cámara está lista —a veces medio
/// segundo—, y en el hilo principal eso es la hoja congelada al abrirse.
///
/// Es `@unchecked Sendable` porque `AVCaptureSession` no lo declara. Es seguro
/// tal y como se usa: la configuración termina en el hilo principal antes de
/// encolar el arranque, y después solo se arranca y se para, siempre en la
/// misma cola serie.
private final class CaptureSessionRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.xilgar.crono.camera")

    func start() {
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
}
