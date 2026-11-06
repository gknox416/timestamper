import SwiftUI

@main
struct TimestamperApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Timestamper", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 620)
        }
        .defaultSize(width: 980, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add WAV Files…") { model.chooseFiles() }
                    .keyboardShortcut("o")
                    .disabled(model.isBusy)
            }
        }
    }
}
