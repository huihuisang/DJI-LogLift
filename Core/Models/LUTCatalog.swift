import CryptoKit
import Foundation

private final class ResourceAnchor {}

public struct LUTDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let packageID: String
    public let file: String
    public let originalName: String
    public let sha256: String
    public let dimension: Int?
    public let shaperDimension: Int?
    public let kind: String
    public let inputProfile: String
    public let outputProfile: String
    public let style: String
    public let version: String

    public var canConvertToRec709: Bool {
        dimension != nil && shaperDimension == nil && kind == "technical"
            && outputProfile == "rec709" && ["dlogM", "dlog", "dlog2"].contains(inputProfile)
    }

    public var profileName: String {
        switch inputProfile {
        case "dlogM": "D-Log M"
        case "dlog": "D-Log"
        case "dlog2": "D-Log 2"
        case "linear": "Linear"
        case "rec709": "Rec.709"
        default: inputProfile
        }
    }
}

public struct DJIProduct: Codable, Hashable, Identifiable, Sendable {
    public let slug: String
    public let title: String
    public var id: String { slug }

    public var name: String {
        let names = [
            "o4-air-unit": "DJI O4 Air Unit Series", "inspire-1": "DJI Inspire 1",
            "inspire-1-pro-and-raw": "DJI Inspire 1 Pro/RAW", "mavic-2": "DJI Mavic 2",
            "phantom-4": "DJI Phantom 4", "phantom-3-pro": "DJI Phantom 3 Pro",
            "phantom-3-adv": "DJI Phantom 3 Advanced", "zenmuse-z3": "DJI Zenmuse Z3",
            "zenmuse-x5": "DJI Zenmuse X5", "zenmuse-x5r": "DJI Zenmuse X5R",
            "zenmuse-x5s": "DJI Zenmuse X5S", "zenmuse-x7": "DJI Zenmuse X7",
        ]
        return names[slug] ?? title
    }
}

public struct LUTPackage: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let sourcePage: URL
    public let products: [DJIProduct]
    public let luts: [LUTDefinition]
}

public struct LUTCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let checkedAt: String
    public let redistributionPermission: String
    public let packages: [LUTPackage]

    public static var resourceRoot: URL {
        get throws {
            guard let url = Bundle(for: ResourceAnchor.self).url(forResource: "DJI", withExtension: nil) else {
                throw LogBatchError.missingResource
            }
            return url
        }
    }

    public static func load() throws -> Self {
        let data = try Data(contentsOf: resourceRoot.appendingPathComponent("catalog.json"))
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1 else { throw LogBatchError.missingResource }
        return catalog
    }

    public var products: [DJIProduct] {
        Array(Set(packages.flatMap(\.products))).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var luts: [LUTDefinition] { packages.flatMap(\.luts) }

    public func luts(for productID: String) -> [LUTDefinition] {
        var seen = Set<String>()
        return packages.filter { $0.products.contains { $0.id == productID } }.flatMap(\.luts).filter { lut in
            let key = [lut.sha256, lut.inputProfile, lut.outputProfile, lut.kind, lut.style, lut.version].joined(separator: ":")
            return seen.insert(key).inserted
        }
    }

    public func loadCube(_ lut: LUTDefinition) throws -> CubeLUT {
        let root = try Self.resourceRoot
        let url = root.appendingPathComponent(lut.file).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw LogBatchError.missingResource }
        let data = try Data(contentsOf: url)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard checksum == lut.sha256 else { throw LogBatchError.checksumMismatch }
        return try CubeLUT(data: data)
    }
}

