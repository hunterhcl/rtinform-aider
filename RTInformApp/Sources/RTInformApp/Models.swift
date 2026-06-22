import Foundation

enum Architecture: String, CaseIterable, Identifiable {
    case arm64, amd64

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arm64: "ARM64 (Apple Silicon)"
        case .amd64: "AMD64 (x86_64)"
        }
    }

    var platform: String { "linux/\(rawValue)" }
}

struct ComposeFile {
    let raw: String
    let services: [ComposeService]
    let networks: [String]
    let volumes: [String]
    let images: [String]
}

struct ComposeService: Identifiable {
    let id: String
    let name: String
    var image: String
    var hasBuild: Bool
    var ports: [String]
    var environment: [String: String]
    var envVarNames: [String]
    var dependsOn: [String]
    var links: [String]
    var networks: [String]
    var serviceVolumes: [String]
    var restart: String
    var memoryLimit: String?
    var cpuLimit: String?
}

struct ValidationIssue: Identifiable {
    let id = UUID()
    let type: IssueType
    let service: String
    let message: String

    enum IssueType: String {
        case error, warning, ok
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: LogType
    let message: String

    enum LogType { case info, ok, error }
}

struct ResourceEstimate {
    let services: [ServiceResource]
    let totalMemoryMB: Int
    let totalCPUs: Double
}

struct ServiceResource: Identifiable {
    let id: String
    let name: String
    let memoryMB: Int
    let cpus: Double
    let isExplicit: Bool
}
