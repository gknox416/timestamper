import AppKit
import Combine
import UniformTypeIdentifiers

struct FileRow: Identifiable {
    let id = UUID()
    let source: URL
    var metadata: BWFMetadata?
    var inputError: String?
    var outcome: BatchResult?
}

/// Owns presentation state only. RIFF parsing, timecode, writing, and verification
/// remain in the shared core used by the CLI and its tests.
@MainActor
final class AppModel: ObservableObject {
    @Published var rows: [FileRow] = []
    @Published var frameRate: FrameRate = .fps23_976
    @Published var targetText = "00:00:00:00"
    @Published var destination: URL?
    @Published var isBusy = false
    @Published var activity = ""
    @Published var completed = 0
    @Published var summary: String?
    @Published var message: String?

    private let worker = DispatchQueue(label: "Timestamper.processing", qos: .userInitiated)

    var targetError: String? {
        do { _ = try Timecode(targetText, frameRate: frameRate); return nil }
        catch { return error.localizedDescription }
    }
    var canProcess: Bool { !isBusy && !rows.isEmpty && destination != nil && targetError == nil }

    func chooseFiles() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Add Broadcast WAV files"
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK { self.addFiles(panel.urls) }
        }
    }

    func chooseDestination() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a destination for copies"
        panel.prompt = "Choose Destination"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK {
                self.destination = panel.url
                self.clearResults()
            }
        }
    }

    func clearResults() {
        summary = nil
        for index in rows.indices { rows[index].outcome = nil }
    }

    func remove(_ id: UUID) {
        guard !isBusy else { return }
        rows.removeAll { $0.id == id }
        clearResults()
    }

    func clear() {
        guard !isBusy else { return }
        rows.removeAll()
        summary = nil
    }

    func addFiles(_ urls: [URL]) {
        guard !isBusy else { return }
        let existing = Set(rows.map { $0.source.standardizedFileURL })
        var seen = existing
        let newURLs = urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }
        guard !newURLs.isEmpty else { return }
        clearResults()
        isBusy = true
        activity = "Reading files…"
        let additions = newURLs.map { FileRow(source: $0) }
        rows.append(contentsOf: additions)
        worker.async {
            for row in additions {
                var updated = row
                do {
                    let reader = try RIFFReader(url: row.source)
                    let layout = try reader.readLayout()
                    updated.metadata = layout.metadata
                    _ = try ProToolsMetadata.inspect(data: reader.data, layout: layout)
                } catch { updated.inputError = error.localizedDescription }
                let inspected = updated
                DispatchQueue.main.async {
                    if let index = self.rows.firstIndex(where: { $0.id == inspected.id }) {
                        self.rows[index] = inspected
                    }
                }
            }
            DispatchQueue.main.async { self.isBusy = false; self.activity = "" }
        }
    }

    func process() {
        guard canProcess, let destination else { return }
        do {
            let target = try Timecode(targetText, frameRate: frameRate)
            let sources = rows.map(\.source)
            let rate = frameRate
            clearResults()
            completed = 0
            activity = "Creating and verifying copies…"
            isBusy = true
            worker.async {
                do {
                    let results = try BatchProcessor.process(sources: sources, destinationDirectory: destination,
                                                            target: target, frameRate: rate) { result in
                        DispatchQueue.main.async {
                            if let index = self.rows.firstIndex(where: { $0.source == result.source }) {
                                self.rows[index].outcome = result
                            }
                            self.completed += 1
                        }
                    }
                    let successes = results.filter { if case .success = $0.outcome { return true }; return false }.count
                    DispatchQueue.main.async {
                        self.summary = "\(successes) verified · \(results.count - successes) failed · \(results.count) total"
                        self.isBusy = false
                        self.activity = ""
                    }
                } catch {
                    let description = error.localizedDescription
                    DispatchQueue.main.async {
                        self.message = description
                        self.summary = "Batch could not start. No copies were created."
                        self.isBusy = false
                        self.activity = ""
                    }
                }
            }
        } catch { message = error.localizedDescription }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
