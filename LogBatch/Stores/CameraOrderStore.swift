import Foundation
import LogBatchCore
import Observation

@MainActor @Observable
final class CameraOrderStore {
    static let preferenceKey = "gallery.promotedCameraIDs"
    private static let defaultOrder = [
        "nano", "osmo-pocket-4p", "osmo-pocket-4", "osmo-pocket-3", "osmo-action-6", "osmo-action-5-pro",
        "mini-5-pro", "air-3s", "mavic-4-pro", "avata-2", "360-2", "360",
    ]

    private(set) var promotedIDs = [String]()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var seen = Set<String>()
        promotedIDs = (defaults.stringArray(forKey: Self.preferenceKey) ?? []).filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
    }

    func orderedProducts(_ products: [DJIProduct]) -> [DJIProduct] {
        var ranks = [String: Int]()
        for id in promotedIDs + Self.defaultOrder where ranks[id] == nil {
            ranks[id] = ranks.count
        }
        return products.sorted { left, right in
            let leftRank = ranks[left.id] ?? Int.max
            let rightRank = ranks[right.id] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            let names = left.name.localizedStandardCompare(right.name)
            return names == .orderedSame ? left.id < right.id : names == .orderedAscending
        }
    }

    @discardableResult
    func moveToFront(_ id: String, among products: [DJIProduct]) -> Bool {
        guard products.contains(where: { $0.id == id }), orderedProducts(products).first?.id != id else { return false }
        promotedIDs.removeAll { $0 == id }
        promotedIDs.insert(id, at: 0)
        defaults.set(promotedIDs, forKey: Self.preferenceKey)
        return true
    }
}
