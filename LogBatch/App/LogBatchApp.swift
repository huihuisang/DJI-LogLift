import FinderSync
import SwiftUI

@main
struct LogBatchApp: App {
    @State private var cameraOrder = CameraOrderStore()

    var body: some Scene {
        WindowGroup("LogLift for DJI") {
            ContentView()
                .environment(cameraOrder)
                .modifier(StudioPreviewOptions())
                .frame(minWidth: 1100, minHeight: 760)
        }
        .defaultSize(width: 1280, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appSettings) {
                Link("Privacy Policy…", destination: URL(string: "https://github.com/huihuisang/DJI-LogLift/blob/master/docs/PRIVACY.md")!)
                Button("Finder Extension…") { FIFinderSyncController.showExtensionManagementInterface() }
            }
        }
    }
}

