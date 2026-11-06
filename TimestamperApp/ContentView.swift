import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timestamper").font(.largeTitle.bold())
                    Text("Set a new start time.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Files…", systemImage: "plus") { model.chooseFiles() }
                    .disabled(model.isBusy)
            }

            files

            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target start timecode").font(.headline)
                    TextField("00:00:00:00", text: $model.targetText)
                        .font(.system(size: 25, weight: .medium, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                        .accessibilityLabel("Target start timecode")
                    if let error = model.targetError {
                        Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(model.frameRate.isDropFrame ? "HH:MM:SS;FF · drop-frame" : "HH:MM:SS:FF")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frame rate").font(.headline)
                    Picker("Frame rate", selection: $model.frameRate) {
                        ForEach(FrameRate.allCases, id: \.self) { rate in Text(rate.name).tag(rate) }
                    }
                    .labelsHidden().frame(width: 170)
                    Text("Used for both current and target timecode.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .disabled(model.isBusy)
            .onChange(of: model.targetText) { _, _ in model.clearResults() }
            .onChange(of: model.frameRate) { _, _ in model.clearResults() }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Destination").font(.headline)
                    Spacer()
                    Button("Choose Folder…") { model.chooseDestination() }.disabled(model.isBusy)
                }
                Text(model.destination?.path ?? "Choose where to save the processed copies")
                    .foregroundStyle(model.destination == nil ? .secondary : .primary)
                    .lineLimit(2).textSelection(.enabled)
                Text("Filenames stay unchanged. Originals are preserved. Existing files are never overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    if model.isBusy {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(model.activity)
                            if model.completed > 0 { Text("\(model.completed)/\(model.rows.count)").monospacedDigit() }
                        }
                    } else if let summary = model.summary {
                        Text(summary).fontWeight(.medium)
                    } else {
                        Text("\(model.rows.count) file\(model.rows.count == 1 ? "" : "s") in batch")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.summary != nil, let destination = model.destination {
                    Button("Show Output Folder") { model.reveal(destination) }
                }
                Button("Create Copies", systemImage: "doc.on.doc") { model.process() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canProcess)
            }
        }
        .padding(26)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Couldn’t complete the operation", isPresented: Binding(
            get: { model.message != nil }, set: { if !$0 { model.message = nil } }
        )) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files").font(.headline)
                Spacer()
                Text("Current start uses \(model.frameRate.name) fps").font(.caption).foregroundStyle(.secondary)
                Button("Clear") { model.clear() }.disabled(model.isBusy || model.rows.isEmpty)
            }.padding(14)
            Divider()
            if model.rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 34)).foregroundStyle(.tint)
                    Text("Drop Broadcast WAV files here").font(.title3.weight(.medium))
                    Text("Or use Add Files to choose one or more files.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            fileRow(row).padding(12)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isDropTarget ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isDropTarget ? 2 : 1))
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isBusy else { return false }
            model.addFiles(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTarget = $0 }
    }

    private func fileRow(_ row: FileRow) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "waveform").foregroundStyle(.secondary).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.source.lastPathComponent).fontWeight(.medium).textSelection(.enabled)
                Text(row.source.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).help(row.source.path)
                if let metadata = row.metadata {
                    HStack(spacing: 10) {
                        Text("\(metadata.sampleRate) Hz")
                        Text("\(metadata.timeReference) samples")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if let outcome = row.outcome {
                    switch outcome.outcome {
                    case .success:
                        Label("Verified copy", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            .font(.caption)
                        Button("Show in Finder") { model.reveal(outcome.destination) }.font(.caption)
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                } else if let error = row.inputError {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                if let metadata = row.metadata {
                    if let tc = try? Timecode.from(timeReference: metadata.timeReference,
                                                   sampleRate: metadata.sampleRate, frameRate: model.frameRate) {
                        Text(tc.description).font(.system(.body, design: .monospaced))
                    } else {
                        Text("Outside TC range").font(.caption).foregroundStyle(.secondary)
                    }
                } else if row.inputError == nil { Text("Reading…").foregroundStyle(.secondary) }
                Text("Current start").font(.caption2).foregroundStyle(.secondary)
            }
            Button { model.remove(row.id) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Remove \(row.source.lastPathComponent)").accessibilityLabel("Remove \(row.source.lastPathComponent)")
                .disabled(model.isBusy)
        }
    }
}
