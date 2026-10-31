import Foundation

public struct CubeLUT: Sendable {
    public let dimension: Int
    public let rgbaData: Data
    public let domainMin: SIMD3<Float>
    public let domainMax: SIMD3<Float>

    public init(data: Data) throws {
        // Some official files use GB18030 in comments and TITLE. Numeric rows remain ASCII.
        let text = String(decoding: data, as: UTF8.self)
        var dimension: Int?
        var minimum = SIMD3<Float>(repeating: 0)
        var maximum = SIMD3<Float>(repeating: 1)
        var values = [Float]()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let key = fields.first else { continue }
            switch key {
            case "TITLE": continue
            case "LUT_1D_SIZE", "LUT_1D_INPUT_RANGE": throw LogBatchError.unsupportedCube
            case "LUT_3D_SIZE":
                guard values.isEmpty, dimension == nil, fields.count == 2,
                      let size = Int(fields[1]), (2...128).contains(size) else { throw LogBatchError.invalidCube }
                dimension = size
                values.reserveCapacity(size * size * size * 4)
            case "DOMAIN_MIN", "DOMAIN_MAX":
                guard values.isEmpty, fields.count == 4 else { throw LogBatchError.invalidCube }
                let vector = try Self.vector(fields.dropFirst())
                if key == "DOMAIN_MIN" { minimum = vector } else { maximum = vector }
            case "LUT_3D_INPUT_RANGE":
                guard values.isEmpty, fields.count == 3, let low = Float(fields[1]),
                      let high = Float(fields[2]), low.isFinite, high.isFinite, low < high else {
                    throw LogBatchError.invalidCube
                }
                minimum = .init(repeating: low)
                maximum = .init(repeating: high)
            default:
                guard let size = dimension, values.count < size * size * size * 4 else {
                    throw LogBatchError.invalidCube
                }
                let vector = try Self.vector(fields[...])
                values.append(contentsOf: [vector.x, vector.y, vector.z, 1])
            }
        }
        guard let size = dimension, values.count == size * size * size * 4,
              minimum.x < maximum.x, minimum.y < maximum.y, minimum.z < maximum.z else {
            throw LogBatchError.invalidCube
        }
        self.dimension = size
        domainMin = minimum
        domainMax = maximum
        rgbaData = values.withUnsafeBytes { Data($0) }
    }

    private static func vector(_ fields: ArraySlice<Substring>) throws -> SIMD3<Float> {
        let numbers = fields.compactMap { Float($0) }
        guard numbers.count == 3, fields.count == 3, numbers.allSatisfy(\.isFinite) else {
            throw LogBatchError.invalidCube
        }
        return SIMD3(numbers[0], numbers[1], numbers[2])
    }
}

