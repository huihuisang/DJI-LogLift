import Darwin
import Foundation

@main
enum PrepareProductArtwork {
    static func main() {
        do {
            guard CommandLine.arguments.count == 3 else {
                throw NSError(domain: "ProductArtwork", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Usage: PrepareProductArtwork <source-directory> <output-directory>",
                ])
            }
            try ProductArtworkProcessor.prepare(
                sourceRoot: URL(fileURLWithPath: CommandLine.arguments[1]),
                outputRoot: URL(fileURLWithPath: CommandLine.arguments[2])
            )
        } catch {
            FileHandle.standardError.write(Data("error: Product artwork preparation failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
