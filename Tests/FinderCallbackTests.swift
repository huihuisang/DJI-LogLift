import Foundation
import XCTest

final class FinderCallbackTests: XCTestCase {
    @MainActor
    func testMenuActionCanArriveOnTheFinderXPCQueue() async {
        let extensionObject = FinderSync()
        await Task.detached {
            // Finder invokes Objective-C menu actions from its XPC connection queue.
            _ = extensionObject.perform(NSSelectorFromString("importVideos"))
        }.value
    }
}
