import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// El código de desarme dibujado como QR, para imprimirlo o guardarlo.
///
/// Sirve para cualquier código registrado, no solo para los que genera Crono:
/// el emparejado va por el contenido, así que el QR de un código de barras
/// desarma igual que el propio bote. Es la salida si el bote se acaba.
struct PrintableCodeView: View {
    let value: String
    let hint: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = Self.qrImage(for: value) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding()
                        .background(.white, in: .rect(cornerRadius: 16))
                        .accessibilityLabel(Text("Código QR de desarme"))

                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview(title, image: Image(uiImage: image))
                    ) {
                        Label("Imprimir o compartir", systemImage: "printer")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ContentUnavailableView("No se pudo dibujar el código", systemImage: "qrcode")
                }

                Text("Ponlo lejos de la cama: en el baño o junto a la cafetera.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("Código de desarme"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private var title: String {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Código de Crono" : "Código de Crono · \(trimmed)"
    }

    /// El QR a una escala que se imprime nítido.
    ///
    /// Se escala en Core Image, píxel a píxel, y no al dibujar: ampliar una
    /// imagen de 25 px al tamaño de una hoja la emborrona, y un QR emborronado
    /// es justo el que la cámara no lee a oscuras.
    static func qrImage(for value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 16, y: 16))
        else { return nil }

        guard let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    PrintableCodeView(value: DisarmCode.makeSecret(), hint: "el baño")
}
