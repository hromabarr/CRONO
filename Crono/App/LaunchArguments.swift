#if DEBUG
import Foundation
import SwiftData

/// Argumentos de lanzamiento para las capturas automáticas en CI.
///
/// Todo el archivo va entre `#if DEBUG`, así que nada de esto existe en la
/// compilación Release que acaba en el `.ipa`: la app publicada no puede
/// sembrarse con datos falsos ni abrirse en una pestaña arbitraria.
///
/// Se usa esta vía en lugar de un objetivo de pruebas de interfaz porque para
/// hacer una captura de cada pestaña basta con arrancar la app ya situada
/// donde toca. Montar XCUITest solo para pulsar tres botones sería mucho
/// aparato para muy poco.
enum LaunchArguments {

    /// `-seedSampleData` rellena la app con el historial de ejemplo.
    static var shouldSeedSampleData: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedSampleData")
    }

    /// `-startTab today|reminders|habits` abre directamente esa sección.
    ///
    /// Ya no acepta `history`: Historial dejó de ser pestaña y se abre empujado
    /// desde Hábitos, así que un argumento de lanzamiento no puede llegar hasta
    /// él sin navegar. Las capturas automáticas cubren las tres pestañas.
    static var initialTab: AppTab? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-startTab"),
              arguments.index(after: flagIndex) < arguments.endIndex
        else { return nil }

        switch arguments[arguments.index(after: flagIndex)] {
        case "today": return .today
        case "reminders": return .reminders
        case "habits": return .habits
        default: return nil
        }
    }

    /// Siembra datos de ejemplo solo si la base está vacía.
    ///
    /// El guardián importa: la sesión de capturas arranca la app seis veces
    /// —tres pestañas por dos apariencias— sobre el mismo contenedor. Sin él,
    /// cada arranque duplicaría los hábitos y la sexta captura mostraría
    /// treinta filas repetidas.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard shouldSeedSampleData else { return }

        let existing = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        guard existing == 0 else { return }

        PreviewData.seed(into: context)
    }
}
#endif

extension AppTab {
    /// Pestaña con la que arranca la app.
    ///
    /// En Release siempre es Hoy; en Debug la puede fijar un argumento de
    /// lanzamiento para las capturas automáticas.
    static var initial: AppTab {
        // El `return` es explícito a propósito: el retorno implícito de una
        // propiedad de una sola expresión no se lleva bien con las ramas de
        // `#if`, porque el cuerpo deja de ser una única expresión.
        #if DEBUG
        return LaunchArguments.initialTab ?? .today
        #else
        return .today
        #endif
    }
}
