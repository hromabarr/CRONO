@preconcurrency import AVFoundation
import SwiftUI

/// Selector de sonido que lo hace sonar al elegirlo.
///
/// Elegir un sonido de alarma por el nombre, sin oírlo, es elegir a ciegas.
struct SoundPicker: View {
    let title: String
    @Binding var selection: AlarmSound

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(AlarmSound.allCases) { sound in
                Text(sound.label).tag(sound)
            }
        }
        .onChange(of: selection) { _, sound in
            SoundPreview.shared.play(sound)
        }
        .onDisappear { SoundPreview.shared.stop() }
    }
}

/// Reproduce unos segundos de un sonido de alarma.
@MainActor
final class SoundPreview {
    static let shared = SoundPreview()

    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ sound: AlarmSound) {
        stop()
        // El del sistema no es un archivo de la app y no se puede reproducir
        // desde aquí: no suena nada, que es mejor que sonar otro.
        guard let name = sound.fileName,
              let url = Bundle.main.url(forResource: name, withExtension: nil)
        else { return }

        // `.playback` para que se oiga aunque el interruptor de silencio esté
        // puesto: la alarma de verdad también sonará.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()

        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
