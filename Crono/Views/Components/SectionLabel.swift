import SwiftUI

/// Cabecera de sección en las pantallas que no usan `List`.
///
/// Estaba duplicada como método privado en las tres pantallas. Extraerla no es
/// solo higiene: los cuerpos de esas vistas eran tan grandes que el inferidor de
/// tipos de Swift se rendía, y cada trozo que sale ayuda a que vuelva a compilar.
struct SectionLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .padding(.horizontal, 4)
    }
}
