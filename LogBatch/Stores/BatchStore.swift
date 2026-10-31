import AppKit
import Foundation
import LogBatchCore
import Observation
import UniformTypeIdentifiers

struct BatchItem: Identifiable {
    enum Status {
        case waiting, processing, completed, failed, cancelled

        var title: String {
            switch self {
            case .waiting: String(localized: "Ready")
            case .processing: String(localized: "Converting")
            case .completed: String(localized: "Completed")
            case .failed: String(localized: "Failed")
            case .cancelled: String(localized: "Cancelled")
            }
        }
    }

    let id = UUID()
    let url: URL
    var status = Status.waiting
    var progress = 0.0
    var error: String?
    var output: URL?
    var thumbnail: CGImage?
    var recordingDate: Date?
    var hasLoadedDetails = false
}

@MainActor @Observable
final class BatchStore {
    static let suppressExportReminderKey = "export.suppressesLogReminder"
    let catalog: LUTCatalog?
    let playback = PreviewPlayback()
    var selectedProductID: String? = "nano"
    var selectedLUTID: String?
    var selectedItemID: UUID?
    var items = [BatchItem]()
    var outputDirectory: URL?
    var showsExportConfirmation = false
    var suppressExportReminder = false
    var message: String?
    var preview: PreviewImages?
    var previewError: String?
    var isLoadingPreview = false
    private(set) var showsExportSuccess = false
    @ObservationIgnored private var scopes = [SecurityScope]()
    private struct ImportRequest {
        let roots: [URL]
        let needsFolderAccess: Bool
    }
    @ObservationIgnored private var pendingImports = [ImportRequest]()
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let destinations: ExportDestinationStore
    @ObservationIgnored private let outputFolderChooser: @MainActor (URL?) -> URL?
    @ObservationIgnored private let importAccess: ImportAccessStore
    @ObservationIgnored private let importFolderChooser: @MainActor (URL) -> URL?
    @ObservationIgnored private var isChoosingOutput = false
    @ObservationIgnored private var isAwaitingExportConfirmation = false
    @ObservationIgnored private let notifications: (any ExportNotifying)?
    @ObservationIgnored private var successResetTask: Task<Void, Never>?
    var isProcessing = false {
        didSet { if !isProcessing { importNextBatch() } }
    }
    var isImporting = false

    init(defaults: UserDefaults = .standard, notifications: (any ExportNotifying)? = nil,
         outputFolderChooser: (@MainActor (URL?) -> URL?)? = nil,
         importFolderChooser: (@MainActor (URL) -> URL?)? = nil) {
        self.defaults = defaults
        destinations = ExportDestinationStore(defaults: defaults)
        self.outputFolderChooser = outputFolderChooser ?? Self.presentOutputFolder
        importAccess = ImportAccessStore(defaults: defaults)
        self.importFolderChooser = importFolderChooser ?? Self.presentImportFolder
        self.notifications = notifications
        do {
            let catalog = try LUTCatalog.load()
            self.catalog = catalog
            selectedLUTID = catalog.luts(for: "nano").first(where: \.canConvertToRec709)?.id
        } catch {
            catalog = nil
            message = error.localizedDescription
        }
        outputDirectory = destinations.restore()
    }

    var availableLUTs: [LUTDefinition] { catalog?.luts(for: selectedProductID ?? "") ?? [] }
    var selectedLUT: LUTDefinition? { availableLUTs.first { $0.id == selectedLUTID } }
    var selectedItem: BatchItem? { items.first { $0.id == selectedItemID } }
    var previewID: String { "\(selectedItemID?.uuidString ?? ""):\(selectedLUTID ?? "")" }
    var canStart: Bool {
        !isProcessing && !isImporting && selectedLUT?.canConvertToRec709 == true
            && items.contains { $0.status != .completed }
    }

    func selectCamera() {
        selectedLUTID = availableLUTs.first(where: \.canConvertToRec709)?.id ?? availableLUTs.first?.id
        cancelExportConfirmation()
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose videos or a folder of DJI footage.")
        panel.prompt = String(localized: "Add Videos")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .folder]
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func add(_ roots: [URL]) {
        enqueueImport(roots, needsFolderAccess: false)
    }

    func importFromFinder(_ files: [URL]) {
        let files = VideoFiles.requestedSelection(from: files)
        guard !files.isEmpty else {
            message = String(localized: "No supported videos were found. Choose MOV, MP4, or M4V files.")
            return
        }
        enqueueImport(files, needsFolderAccess: true)
    }

    private func enqueueImport(_ roots: [URL], needsFolderAccess: Bool) {
        let roots = roots.filter(\.isFileURL)
        guard !roots.isEmpty else { return }
        scopes.append(contentsOf: roots.map(SecurityScope.init))
        pendingImports.append(ImportRequest(roots: roots, needsFolderAccess: needsFolderAccess))
        importNextBatch()
    }

    private func importNextBatch() {
        guard !isProcessing && !isImporting && !pendingImports.isEmpty else { return }
        let request = pendingImports.removeFirst()
        resetExportSuccess()
        isImporting = true
        Task {
            defer {
                isImporting = false
                importNextBatch()
            }
            if request.needsFolderAccess {
                do {
                    guard try importAccess.authorize(request.roots, chooseFolder: importFolderChooser) else { return }
                } catch {
                    message = error.localizedDescription
                    return
                }
            }
            let roots = request.needsFolderAccess ? VideoFiles.selection(from: request.roots) : request.roots
            let videos = await Task.detached(priority: .userInitiated) {
                Self.collectVideos(roots)
            }.value
            var existing = Set(items.map { $0.url.standardizedFileURL })
            for url in videos where existing.insert(url.standardizedFileURL).inserted {
                items.append(BatchItem(url: url))
            }
            if selectedItemID == nil { selectedItemID = items.first?.id }
            if videos.isEmpty { message = String(localized: "No supported videos were found. Choose MOV, MP4, or M4V files.") }
        }
    }

    private static func presentImportFolder(_ directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Allow access to the folder that contains these videos. LogLift remembers read-only access for future imports.")
        panel.prompt = String(localized: "Allow Folder")
        panel.directoryURL = directory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @discardableResult
    func chooseOutput() -> Bool {
        guard !isProcessing, !isChoosingOutput else { return false }
        isChoosingOutput = true
        defer { isChoosingOutput = false }
        playback.pause()
        guard let url = outputFolderChooser(outputDirectory) else { return false }
        do {
            try destinations.remember(url)
            outputDirectory = url
            return true
        } catch {
            message = String(localized: "The export folder could not be saved. Choose another folder.")
            return false
        }
    }

    private static func presentOutputFolder(_ current: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose a folder for converted videos. Original files stay unchanged.")
        panel.prompt = String(localized: "Choose Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = current
        return panel.runModal() == .OK ? panel.url : nil
    }

    func loadPreview() async {
        let startAt = playback.sourceURL == selectedItem?.url ? playback.position : 0
        playback.stop()
        preview = nil; previewError = nil
        isLoadingPreview = false
        guard let item = selectedItem, let lut = selectedLUT, lut.canConvertToRec709, let catalog else { return }
        let identifier = previewID
        isLoadingPreview = true
        defer { if previewID == identifier { isLoadingPreview = false } }
        do {
            let (cube, images) = try await Task.detached(priority: .userInitiated) {
                let cube = try catalog.loadCube(lut)
                return (cube, try await VideoPreview.load(source: item.url, cube: cube))
            }.value
            guard !Task.isCancelled, previewID == identifier else { return }
            preview = images
            try await playback.prepare(source: item.url, cube: cube, poster: images, startAt: startAt)
        } catch {
            guard !Task.isCancelled, previewID == identifier else { return }
            preview = nil
            previewError = error.localizedDescription
        }
    }

    func start() {
        guard canStart, !isAwaitingExportConfirmation, !isChoosingOutput else { return }
        let hasDirectory = outputDirectory.map { destinations.access($0) } ?? false
        if !hasDirectory {
            outputDirectory = destinations.restore()
            if outputDirectory == nil, !chooseOutput() { return }
        }
        guard canStart, let outputDirectory, destinations.access(outputDirectory) else { return }
        if defaults.bool(forKey: Self.suppressExportReminderKey) {
            convert()
        } else {
            suppressExportReminder = false
            isAwaitingExportConfirmation = true
            showsExportConfirmation = true
        }
    }

    func confirmExport() {
        let wasAwaitingConfirmation = isAwaitingExportConfirmation
        let suppressReminder = suppressExportReminder
        cancelExportConfirmation()
        guard wasAwaitingConfirmation, canStart, let outputDirectory, destinations.access(outputDirectory) else { return }
        if suppressReminder { defaults.set(true, forKey: Self.suppressExportReminderKey) }
        convert()
    }

    func cancelExportConfirmation() {
        showsExportConfirmation = false
        suppressExportReminder = false
        isAwaitingExportConfirmation = false
    }

    private func convert() {
        guard canStart, let catalog, let lut = selectedLUT, let directory = outputDirectory,
              destinations.access(directory) else { return }
        playback.pause()
        resetExportSuccess()
        notifications?.requestAuthorization()
        let batchIDs = Set(items.filter { $0.status != .completed }.map(\.id))
        isProcessing = true
        message = nil
        worker = Task {
            defer { isProcessing = false; worker = nil }
            do {
                let cube = try await Task.detached { try catalog.loadCube(lut) }.value
                for index in items.indices where items[index].status != .completed {
                    try Task.checkCancellation()
                    items[index].status = .processing
                    items[index].progress = 0
                    items[index].error = nil
                    let source = items[index].url
                    let identifier = items[index].id
                    let stem = source.deletingPathExtension().lastPathComponent
                    let output = directory.appendingPathComponent(stem + "-rec709.mp4")
                    do {
                        try await VideoExporter.export(source: source, destination: output, cube: cube) { fraction in
                            Task { @MainActor in
                                guard let row = self.items.firstIndex(where: { $0.id == identifier }),
                                      self.items[row].status == .processing else { return }
                                self.items[row].progress = fraction
                            }
                        }
                        items[index].status = .completed
                        items[index].progress = 1
                        items[index].output = output
                    } catch is CancellationError {
                        items[index].status = .cancelled
                        break
                    } catch {
                        items[index].status = .failed
                        items[index].error = error.localizedDescription
                    }
                }
                let completedIDs = Set(items.filter { $0.status == .completed }.map(\.id))
                if !Task.isCancelled && batchIDs.isSubset(of: completedIDs) {
                    showExportSuccess(count: batchIDs.count, directory: directory)
                }
            } catch is CancellationError {
                return
            } catch { message = error.localizedDescription }
        }
    }

    func cancel() { worker?.cancel() }

    private func showExportSuccess(count: Int, directory: URL) {
        showsExportSuccess = true
        successResetTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.showsExportSuccess = false
            self?.successResetTask = nil
        }
        if let notifications {
            Task { await notifications.exportCompleted(count: count, directory: directory) }
        }
    }

    private func resetExportSuccess() {
        successResetTask?.cancel()
        successResetTask = nil
        showsExportSuccess = false
    }

    func selectItem(_ id: UUID?) {
        guard let id, items.contains(where: { $0.id == id }) else { return }
        selectedItemID = id
    }

    func loadClipDetails(for id: UUID) async {
        guard let item = items.first(where: { $0.id == id }), !item.hasLoadedDetails else { return }
        let (image, date) = await Task.detached(priority: .utility) {
            let date = await ClipMetadata.recordingDate(source: item.url)
            let image = try? await VideoPreview.thumbnail(source: item.url)
            return (image, date)
        }.value
        guard !Task.isCancelled, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].thumbnail = image
        items[index].recordingDate = date
        items[index].hasLoadedDetails = true
    }

    func remove(_ id: UUID) {
        guard !isProcessing && !isImporting,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if selectedItemID == id {
            selectedItemID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
            resetPreview()
        }
    }

    func clear() {
        guard !isProcessing && !isImporting else { return }
        resetExportSuccess()
        items.removeAll(); selectedItemID = nil
        resetPreview()
        scopes.removeAll()
    }

    private func resetPreview() {
        playback.stop()
        preview = nil
        previewError = nil
        isLoadingPreview = false
    }

    private nonisolated static func collectVideos(_ roots: [URL]) -> [URL] {
        var urls = [URL]()
        for root in roots {
            let isDirectory = (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory, let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let url as URL in enumerator {
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values?.isRegularFile == true, values?.isSymbolicLink != true,
                       VideoFiles.extensions.contains(url.pathExtension.lowercased()) { urls.append(url) }
                }
            } else if VideoFiles.supports(root) { urls.append(root) }
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

