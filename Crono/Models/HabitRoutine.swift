import Foundation

/// Moments of the day, independent of notification and alarm times.
enum HabitRoutine: String, CaseIterable, Identifiable, Sendable {
    case morning
    case anytime
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Mañana"
        case .anytime: "Durante el día"
        case .evening: "Noche"
        }
    }

    var symbolName: String {
        switch self {
        case .morning: "sun.max"
        case .anytime: "sun.haze"
        case .evening: "moon"
        }
    }
}
