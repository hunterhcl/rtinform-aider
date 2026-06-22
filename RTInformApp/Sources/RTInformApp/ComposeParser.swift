import Foundation
import Yams

enum ComposeParser {

    static func parse(_ content: String) throws -> ComposeFile {
        guard let yaml = try Yams.load(yaml: content) as? [String: Any] else {
            throw ComposeError.invalidFormat
        }

        let servicesDict = yaml["services"] as? [String: Any] ?? [:]
        let networksDict = yaml["networks"] as? [String: Any] ?? [:]
        let volumesDict = yaml["volumes"] as? [String: Any] ?? [:]

        var services: [ComposeService] = []
        var allImages: Set<String> = []

        for (name, value) in servicesDict {
            guard let svcDict = value as? [String: Any] else { continue }
            let svc = parseService(name: name, dict: svcDict)
            services.append(svc)
            if !svc.image.isEmpty { allImages.insert(svc.image) }
        }

        services.sort { $0.name < $1.name }

        return ComposeFile(
            raw: content,
            services: services,
            networks: Array(networksDict.keys).sorted(),
            volumes: Array(volumesDict.keys).sorted(),
            images: allImages.sorted()
        )
    }

    private static func parseService(name: String, dict: [String: Any]) -> ComposeService {
        let image = dict["image"] as? String ?? ""
        let hasBuild = dict["build"] != nil
        let ports = (dict["ports"] as? [Any])?.map { String(describing: $0) } ?? []

        var environment: [String: String] = [:]
        var envVarNames: [String] = []
        if let envList = dict["environment"] as? [String] {
            for item in envList {
                let parts = item.split(separator: "=", maxSplits: 1)
                let key = String(parts[0])
                environment[key] = parts.count > 1 ? String(parts[1]) : ""
                envVarNames.append(key)
            }
        } else if let envDict = dict["environment"] as? [String: Any] {
            for (key, value) in envDict.sorted(by: { $0.key < $1.key }) {
                environment[key] = "\(value)"
                envVarNames.append(key)
            }
        }

        var dependsOn: [String] = []
        if let list = dict["depends_on"] as? [String] {
            dependsOn = list
        } else if let map = dict["depends_on"] as? [String: Any] {
            dependsOn = Array(map.keys)
        }

        let links = (dict["links"] as? [String])?.map {
            String($0.split(separator: ":").first ?? Substring($0))
        } ?? []

        var networks: [String] = []
        if let list = dict["networks"] as? [String] {
            networks = list
        } else if let map = dict["networks"] as? [String: Any] {
            networks = Array(map.keys)
        }

        let vols = (dict["volumes"] as? [Any])?.map { String(describing: $0) } ?? []
        let restart = dict["restart"] as? String ?? ""

        var memoryLimit: String?
        var cpuLimit: String?
        if let deploy = dict["deploy"] as? [String: Any],
           let resources = deploy["resources"] as? [String: Any] {
            let limits = resources["limits"] as? [String: Any]
            let reservations = resources["reservations"] as? [String: Any]
            memoryLimit = (limits?["memory"] as? String) ?? (reservations?["memory"] as? String)
            cpuLimit = extractString(limits?["cpus"]) ?? extractString(reservations?["cpus"])
        }

        return ComposeService(
            id: name, name: name, image: image, hasBuild: hasBuild,
            ports: ports, environment: environment, envVarNames: envVarNames.sorted(),
            dependsOn: dependsOn.sorted(), links: links, networks: networks.sorted(),
            serviceVolumes: vols, restart: restart,
            memoryLimit: memoryLimit, cpuLimit: cpuLimit
        )
    }

    private static func extractString(_ value: Any?) -> String? {
        guard let v = value else { return nil }
        if let s = v as? String { return s }
        return "\(v)"
    }

    // MARK: - Analysis

    static func generateSampleEnv(_ compose: ComposeFile) -> String {
        var lines = ["# Auto-generated sample.env", "# Fill in the values for your deployment", ""]
        var seen: Set<String> = []

        for svc in compose.services where !svc.envVarNames.isEmpty {
            lines.append("# === \(svc.name) ===")
            for name in svc.envVarNames where !seen.contains(name) {
                seen.insert(name)
                lines.append("\(name)=")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func checkConnections(_ compose: ComposeFile) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let names = Set(compose.services.map(\.name))

        for svc in compose.services {
            for dep in svc.dependsOn where !names.contains(dep) {
                issues.append(.init(type: .error, service: svc.name,
                    message: "depends_on '\(dep)' — service not found"))
            }
            for link in svc.links where !names.contains(link) {
                issues.append(.init(type: .error, service: svc.name,
                    message: "link '\(link)' — service not found"))
            }
            if svc.image.isEmpty && !svc.hasBuild {
                issues.append(.init(type: .error, service: svc.name,
                    message: "no 'image' or 'build' specified"))
            }
        }

        var hostPorts: [String: String] = [:]
        for svc in compose.services {
            for port in svc.ports {
                let parts = port.split(separator: ":")
                let hp: String? = parts.count == 2 ? String(parts[0]) :
                                   parts.count >= 3 ? String(parts[1]) : nil
                if let hp {
                    if let existing = hostPorts[hp] {
                        issues.append(.init(type: .warning, service: svc.name,
                            message: "host port \(hp) conflicts with '\(existing)'"))
                    } else {
                        hostPorts[hp] = svc.name
                    }
                }
            }
        }

        let definedNets = Set(compose.networks)
        for svc in compose.services {
            for net in svc.networks where net != "default" && !definedNets.isEmpty && !definedNets.contains(net) {
                issues.append(.init(type: .warning, service: svc.name,
                    message: "network '\(net)' not in top-level networks"))
            }
        }

        if issues.isEmpty {
            issues.append(.init(type: .ok, service: "—", message: "All connections and references look valid"))
        }
        return issues
    }

    static func estimateResources(_ compose: ComposeFile) -> ResourceEstimate {
        var services: [ServiceResource] = []
        var totalMem = 0
        var totalCPU = 0.0

        for svc in compose.services {
            let mem = parseMemory(svc.memoryLimit ?? "256M")
            let cpu = Double(svc.cpuLimit ?? "0.5") ?? 0.5
            let explicit = svc.memoryLimit != nil || svc.cpuLimit != nil
            services.append(.init(id: svc.name, name: svc.name, memoryMB: mem, cpus: cpu, isExplicit: explicit))
            totalMem += mem
            totalCPU += cpu
        }

        return ResourceEstimate(services: services, totalMemoryMB: totalMem, totalCPUs: totalCPU)
    }

    private static func parseMemory(_ value: String) -> Int {
        let v = value.uppercased().trimmingCharacters(in: .whitespaces)
        let table: [(String, Double)] = [
            ("TB", 1024 * 1024), ("GB", 1024), ("G", 1024),
            ("MB", 1), ("M", 1), ("KB", 1.0 / 1024), ("K", 1.0 / 1024)
        ]
        for (suffix, mult) in table {
            if v.hasSuffix(suffix), let n = Double(v.dropLast(suffix.count)) {
                return Int(n * mult)
            }
        }
        if let bytes = Int(v) { return bytes / (1024 * 1024) }
        return 256
    }
}

enum ComposeError: LocalizedError {
    case invalidFormat
    var errorDescription: String? { "Invalid docker-compose format" }
}
