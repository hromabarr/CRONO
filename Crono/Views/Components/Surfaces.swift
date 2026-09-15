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
    ///
    /// ## Dónde está el vidrio entonces
    ///
    /// Repasado todo el cromo flotante de la app: los botones de las esquinas
    /// son `ToolbarItem`, la barra de abajo es un `TabView` y los formularios
    /// son `.sheet`. Las tres cosas las dibuja el sistema, y el vidrio lo pone
    /// él. No queda ningún control flotante dibujado a mano, así que **no hay
    /// ningún sitio donde llamar a `glassEffect(_:in:)`**.
    ///
    /// Se deja escrito porque la pregunta se vuelve a hacer sola al ver que la
    /// app no menciona Liquid Glass en ninguna parte. Si algún día aparece un
    /// control propio que flote sobre el contenido —una barra de acciones, un
    /// botón suelto—, ese sí lo lleva; el contenido que se desplaza, no.
    func groupedCard(cornerRadius: CGFloat = 18) -> some View {
        background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
