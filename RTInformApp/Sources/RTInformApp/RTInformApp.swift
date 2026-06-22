import SwiftUI

@main
struct RTInformApp: App {
    var body: some Scene {
        WindowGroup("RTInform Container Manager") {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 960, height: 720)
    }
}

@Observable
final class AppState {
    var composeFile: ComposeFile?
    var architecture: Architecture = .arm64
    var logs: [LogEntry] = []
    var isPulling = false
    var isExporting = false
    var containerAvailable: Bool?
    var validationResults: [ValidationIssue] = []
    var sampleEnv: String = ""
    var resourceEstimate: ResourceEstimate?
    var showValidation = false
    var showEnv = false
    var showResources = false
    var showEditor = false
    var editorContent = ""

    var isLoaded: Bool { composeFile != nil }

    func log(_ type: LogEntry.LogType, _ message: String) {
        logs.append(LogEntry(timestamp: .now, type: type, message: message))
    }

    func clearPanels() {
        showValidation = false
        showEnv = false
        showResources = false
        showEditor = false
        validationResults = []
        sampleEnv = ""
        resourceEstimate = nil
    }

    func updateFromCompose() {
        guard let compose = composeFile else { return }
        editorContent = compose.raw
    }
}
