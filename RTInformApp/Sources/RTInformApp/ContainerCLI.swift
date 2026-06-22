import Foundation

enum ContainerCLI {

    static let binaryPath: String = {
        let candidates = [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
            "/usr/bin/container",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["container"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? "container" : out
    }()

    // MARK: - Generic runners

    static func run(_ arguments: [String]) async -> (ok: Bool, stdout: String, stderr: String) {
        await shell(binaryPath, arguments)
    }

    static func shell(_ executable: String, _ arguments: [String]) async -> (ok: Bool, stdout: String, stderr: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    cont.resume(returning: (proc.terminationStatus == 0, out, err))
                } catch {
                    cont.resume(returning: (false, "", error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Container operations

    static func isAvailable() async -> Bool {
        let r = await run(["version"])
        return r.ok
    }

    static func pullImage(_ image: String, platform: String) async -> (ok: Bool, message: String) {
        let r = await run(["pull", "--platform", platform, image])
        return r.ok ? (true, "Pulled: \(image)") : (false, r.stderr.isEmpty ? "Failed" : r.stderr)
    }

    static func saveImage(_ image: String, outputPath: String) async -> (ok: Bool, message: String) {
        let r = await run(["image", "save", "-o", outputPath, image])
        return r.ok ? (true, outputPath) : (false, r.stderr.isEmpty ? "Failed" : r.stderr)
    }

    static func exportImage(_ image: String, platform: String, destDir: URL) async -> (image: String, ok: Bool, path: String, sizeMB: Double, message: String) {
        let safe = image.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "@", with: "_")
        let suffix = platform.replacingOccurrences(of: "/", with: "_")
        let tarURL = destDir.appendingPathComponent("\(safe)_\(suffix).tar")
        let gzURL = destDir.appendingPathComponent("\(safe)_\(suffix).tar.gz")

        let save = await saveImage(image, outputPath: tarURL.path)
        guard save.ok else {
            return (image, false, "", 0, save.message)
        }

        _ = await shell("/usr/bin/gzip", ["-f", tarURL.path])

        let fm = FileManager.default
        let finalURL = fm.fileExists(atPath: gzURL.path) ? gzURL : tarURL
        guard fm.fileExists(atPath: finalURL.path) else {
            return (image, false, "", 0, "File not found after export")
        }

        let size = (try? fm.attributesOfItem(atPath: finalURL.path)[.size] as? Int) ?? 0
        return (image, true, finalURL.path, Double(size) / 1_048_576, "OK")
    }

    static func listImages() async -> String {
        let r = await run(["image", "list"])
        return r.stdout
    }
}
