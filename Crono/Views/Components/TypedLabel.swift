import SwiftUI

extension Label where Title == Text, Icon == Image {
    /// `Label` con los tipos genéricos ya cerrados.
    ///
    /// `Label(_:systemImage:)` tiene sobrecargas para `LocalizedStringKey` y
    /// para `StringProtocol`. Dentro de un contenedor genérico —`swipeActions`,
    /// `ContentUnavailableView`, un `ToolbarContentBuilder`— el inferidor de
    /// tipos tiene que probar cada combinación de esas sobrecargas contra los
    /// parámetros del contenedor, y en cuanto hay dos o tres etiquetas juntas se
    /// rinde con «unable to type-check this expression in reasonable time».
    ///
    /// Con `Title == Text` e `Icon == Image` no queda nada que inferir.
    init(text: String, systemImage: String) {
        self.init {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
