@preconcurrency import AVFoundation
import Foundation

/// El lector de verdad: la cámara trasera.
///
/// Solo responde a las preguntas del protocolo —si hay cámara, si hay linterna,
/// si hay permiso—. Leer los códigos lo hace `CodeScannerView`, porque necesita
/// una vista donde enseñar lo que ve la cámara y eso no cabe en un servicio.
@MainActor
final class CameraCodeScanner: CodeScanning {
    var isAvailable: Bool { Self.camera != nil }

    var hasTorch: Bool { Self.camera?.hasTorch ?? false }

    /// Pregunta solo la primera vez. Si el usuario ya dijo que no, iOS no
    /// vuelve a enseñar el diálogo y esto devuelve `false` sin más: lo único útil
    /// entonces es mandarlo a Ajustes.
    func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// La cámara trasera. `nil` en el simulador.
    static var camera: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}
