import Foundation
import LogBatchCore

enum CameraCategory: String, CaseIterable, Identifiable {
    case all, handheld, aerial, cinema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All Cameras")
        case .handheld: String(localized: "Handheld")
        case .aerial: String(localized: "Drones")
        case .cinema: String(localized: "Cinema")
        }
    }

    func includes(_ product: DJIProduct) -> Bool {
        let id = product.id
        let handheld = id == "nano" || id == "360" || id == "360-2" || id.hasPrefix("osmo-")
        let cinema = id.hasPrefix("zenmuse-") || id.hasPrefix("inspire-") || id == "ronin-4d"
        switch self {
        case .all: return true
        case .handheld: return handheld
        case .aerial: return !handheld && !cinema
        case .cinema: return cinema
        }
    }
}

