import SwiftUI

extension View {
    /// Tarjeta agrupada estándar de la app.
    ///
    /// ## Por qué aquí no hay vidrio
    ///
    /// En iOS 26 el sistema aplica Liquid Glass por su cuenta al cromo flotante
    /// —`TabView`, barras de navegación, hojas— sin que haya que pedirlo. Lo que
    /// no debe llevarlo es el contenido que se desplaza: las HIG reservan los
    /// materiales translúcidos para las capas que flotan **sobre** el contenido,
    /// y apilar vidrio sobre vidrio destruye la legibilidad.
    ///
    /// Por eso estas tarjetas usan un fondo sólido del sistema, que además se
    /// adapta solo al Modo Oscuro y a los ajustes de contraste.
    func groupedCard(cornerRadius: CGFloat = 18) -> some View {
        background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
