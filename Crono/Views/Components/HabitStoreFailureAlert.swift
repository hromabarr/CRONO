import SwiftUI

private struct HabitStoreFailureAlert: ViewModifier {
    @Environment(HabitStore.self) private var store

    func body(content: Content) -> some View {
        content.alert("No se pudo guardar", isPresented: Binding(
            get: { store.failure != nil },
            set: { if !$0 { store.failure = nil } }
        )) {
            Button("Entendido") { store.failure = nil }
        } message: {
            Text(store.failure?.message ?? "Vuelve a intentarlo.")
        }
    }
}

extension View {
    func habitStoreFailureAlert() -> some View { modifier(HabitStoreFailureAlert()) }
}
