@preconcurrency import AVFoundation
import Foundation

enum ClipMetadata {
    static func recordingDate(source: URL) async -> Date? {
        let asset = AVURLAsset(url: source)
        let metadata = (try? await asset.load(.metadata)) ?? []
        let cameraDates = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataCreationDate)
        for item in cameraDates {
            if let date = await date(from: item) { return date }
        }
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return await date(from: item)
    }

    private static func date(from item: AVMetadataItem) async -> Date? {
        if let date = try? await item.load(.dateValue) { return date }
        guard let text = try? await item.load(.stringValue) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
