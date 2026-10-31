import Foundation

public enum LogBatchError: Error, LocalizedError, Equatable, Sendable {
    case missingResource
    case checksumMismatch
    case invalidCube
    case unsupportedCube
    case unsupportedMedia
    case processingFailed
    case outputExists

    public var errorDescription: String? {
        let bundle = Bundle(for: ErrorResourceAnchor.self)
        return switch self {
        case .missingResource: String(localized: "Bundled LUT resources are missing or invalid.", bundle: bundle)
        case .checksumMismatch: String(localized: "The LUT file failed its integrity check.", bundle: bundle)
        case .invalidCube: String(localized: "The CUBE file is incomplete or invalid.", bundle: bundle)
        case .unsupportedCube: String(localized: "This LUT format is not supported for conversion yet.", bundle: bundle)
        case .unsupportedMedia: String(localized: "This video format or track layout is not supported.", bundle: bundle)
        case .processingFailed: String(localized: "Video processing failed.", bundle: bundle)
        case .outputExists: String(localized: "An output file already exists. Choose another folder or rename the source.", bundle: bundle)
        }
    }
}

private final class ErrorResourceAnchor {}

