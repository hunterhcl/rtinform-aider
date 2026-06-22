import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

private enum Theme {
    static let bg        = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface   = Color(red: 0.10, green: 0.11, blue: 0.15)
    static let surface2  = Color(red: 0.14, green: 0.15, blue: 0.21)
    static let border    = Color(red: 0.18, green: 0.19, blue: 0.26)
    static let accent    = Color(red: 0.42, green: 0.54, blue: 1.0)
    static let green     = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let red       = Color(red: 0.97, green: 0.44, blue: 0.44)
    static let orange    = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let textDim   = Color(red: 0.55, green: 0.56, blue: 0.64)
}

// MARK: - ContentView

struct ContentView: View {
    @State private var state = AppState()
    @State private var showFilePicker = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                VStack(spacing: 16) {
                    dropZone
                    if state.isLoaded { controlBar }
                    if let compose = state.composeFile { infoPanels(compose) }
                    if state.showValidation { validationPanel }
                    if state.showEnv { envPanel }
                    if state.showResources, let est = state.resourceEstimate { resourcePanel(est) }
                    if !state.logs.isEmpty { logPanel }
                }
                .padding(20)
            }
        }
        .background(Theme.bg)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.yaml, .plainText, .data]) { result in
            if case .success(let url) = result { loadFile(url) }
        }
        .task { state.containerAvailable = await ContainerCLI.isAvailable() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("RTInform").foregroundStyle(Theme.accent).fontWeight(.bold)
            + Text(" Container Manager")
            Spacer()
            statusBadge
        }
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Divider().background(Theme.border) }
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch state.containerAvailable {
            case .some(true):  return ("container CLI: ok", Theme.green)
            case .some(false): return ("container CLI: not found", Theme.red)
            case .none:        return ("checking...", Theme.textDim)
            }
        }()
        return Text(label)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.surface2)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textDim)
            Text("Drop docker-compose.yaml here").fontWeight(.semibold)
            Text("or click to select file")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 2, dash: [8]))
        )
        .onTapGesture { showFilePicker = true }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { loadFile(url) } }
            }
            return true
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            Text("Architecture:").font(.caption).foregroundStyle(Theme.textDim)
            Picker("", selection: $state.architecture) {
                ForEach(Architecture.allCases) { arch in
                    Text(arch.displayName).tag(arch)
                }
            }
            .frame(width: 200)
            .labelsHidden()

            Spacer()

            actionButton("Pull All", icon: "arrow.down.circle", primary: true) { pullAll() }
                .disabled(state.isPulling)
            actionButton("Export tar.gz", icon: "archivebox") { exportAll() }
                .disabled(state.isExporting)
            actionButton("Check", icon: "checkmark.shield") { checkConnections() }
            actionButton(".env", icon: "key") { generateEnv() }
            actionButton("Resources", icon: "gauge.medium") { estimateResources() }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private func actionButton(_ title: String, icon: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption).fontWeight(.medium)
        }
        .buttonStyle(.bordered)
        .tint(primary ? Theme.accent : nil)
    }

    // MARK: - Info panels

    private func infoPanels(_ compose: ComposeFile) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            panel("Services", count: compose.services.count) {
                ForEach(compose.services) { svc in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(svc.name).fontWeight(.semibold).font(.caption)
                            Text(svc.image.isEmpty ? "build context" : svc.image)
                                .font(.caption2).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        ForEach(svc.ports, id: \.self) { port in
                            tag(port)
                        }
                        if !svc.restart.isEmpty { tag(svc.restart) }
                    }
                    .padding(.vertical, 4)
                    if svc.id != compose.services.last?.id { Divider().background(Theme.border) }
                }
            }

            panel("Images", count: compose.images.count) {
                ForEach(compose.images, id: \.self) { img in
                    Text(img).font(.caption).fontWeight(.medium).padding(.vertical, 3)
                    if img != compose.images.last { Divider().background(Theme.border) }
                }
            }

            panel("Ports", count: compose.services.flatMap(\.ports).count) {
                let portsMap = Dictionary(grouping: compose.services.filter { !$0.ports.isEmpty }, by: \.name)
                ForEach(portsMap.keys.sorted(), id: \.self) { name in
                    if let svcs = portsMap[name] {
                        HStack {
                            Text(name).font(.caption).fontWeight(.semibold)
                            Spacer()
                            ForEach(svcs.flatMap(\.ports), id: \.self) { p in tag(p) }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            panel("Dependencies", count: compose.services.filter { !$0.dependsOn.isEmpty }.count) {
                let deps = compose.services.filter { !$0.dependsOn.isEmpty }
                if deps.isEmpty {
                    Text("No dependencies").font(.caption).foregroundStyle(Theme.textDim)
                } else {
                    ForEach(deps) { svc in
                        HStack {
                            Text(svc.name).font(.caption).fontWeight(.semibold)
                            Spacer()
                            ForEach(svc.dependsOn, id: \.self) { d in tag(d) }
                        }
                        .padding(.vertical, 3)
                        if svc.id != deps.last?.id { Divider().background(Theme.border) }
                    }
                }
            }
        }
    }

    // MARK: - Validation

    private var validationPanel: some View {
        panel("Validation Results", count: state.validationResults.count, fullWidth: true) {
            ForEach(state.validationResults) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(issueColor(issue.type))
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    Text(issue.service).font(.caption).fontWeight(.semibold).foregroundStyle(Theme.accent)
                    Text(issue.message).font(.caption)
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: - .env

    private var envPanel: some View {
        panel("Sample .env", fullWidth: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(state.sampleEnv)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Spacer()
                    Button("Copy to clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.sampleEnv, forType: .string)
                        state.log(.ok, "sample.env copied to clipboard")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Button("Save to file...") { saveEnvFile() }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Resources

    private func resourcePanel(_ estimate: ResourceEstimate) -> some View {
        panel("Resource Estimates", fullWidth: true) {
            VStack(spacing: 0) {
                HStack {
                    Text("Service").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Memory").frame(width: 80, alignment: .trailing)
                    Text("CPUs").frame(width: 60, alignment: .trailing)
                    Text("Source").frame(width: 70, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .padding(.bottom, 6)

                ForEach(estimate.services) { svc in
                    HStack {
                        Text(svc.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(svc.memoryMB) MB").frame(width: 80, alignment: .trailing)
                        Text(String(format: "%.1f", svc.cpus)).frame(width: 60, alignment: .trailing)
                        Text(svc.isExplicit ? "explicit" : "default")
                            .foregroundStyle(svc.isExplicit ? Theme.green : Theme.textDim)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.vertical, 3)
                    Divider().background(Theme.border)
                }

                HStack {
                    Text("Total").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(estimate.totalMemoryMB) MB").fontWeight(.bold).frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.1f", estimate.totalCPUs)).fontWeight(.bold).frame(width: 60, alignment: .trailing)
                    Text("").frame(width: 70)
                }
                .font(.caption)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LOG").font(.caption2).fontWeight(.semibold)
                    .tracking(0.5).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Clear") { state.logs.removeAll() }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(state.logs) { entry in
                            logLine(entry).id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 200)
                .onChange(of: state.logs.count) { proxy.scrollTo(state.logs.last?.id) }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private func logLine(_ entry: LogEntry) -> some View {
        let color: Color = switch entry.type {
        case .info: Theme.accent
        case .ok: Theme.green
        case .error: Theme.red
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return Text("[\(formatter.string(from: entry.timestamp))] \(entry.message)")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(color)
    }

    // MARK: - Reusable components

    private func panel<Content: View>(_ title: String, count: Int? = nil, fullWidth: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2).fontWeight(.semibold)
                    .tracking(0.5).foregroundStyle(Theme.textDim)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(Theme.border)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface2)

            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(14)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border))
    }

    private func issueColor(_ type: ValidationIssue.IssueType) -> Color {
        switch type {
        case .error: Theme.red
        case .warning: Theme.orange
        case .ok: Theme.green
        }
    }

    // MARK: - Actions

    private func loadFile(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            state.log(.error, "Cannot read file: \(url.lastPathComponent)")
            return
        }

        do {
            let compose = try ComposeParser.parse(content)
            state.composeFile = compose
            state.clearPanels()
            state.log(.ok, "Loaded: \(compose.services.count) services, \(compose.images.count) images")
        } catch {
            state.log(.error, "Parse error: \(error.localizedDescription)")
        }
    }

    private func pullAll() {
        guard let compose = state.composeFile else { return }
        state.isPulling = true
        let platform = state.architecture.platform
        state.log(.info, "Pulling \(compose.images.count) images for \(platform)...")

        Task {
            for image in compose.images {
                let r = await ContainerCLI.pullImage(image, platform: platform)
                await MainActor.run {
                    state.log(r.ok ? .ok : .error, r.ok ? "Pulled: \(image)" : "Failed: \(image) — \(r.message)")
                }
            }
            await MainActor.run { state.isPulling = false }
        }
    }

    private func exportAll() {
        guard let compose = state.composeFile else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        state.isExporting = true
        let platform = state.architecture.platform
        state.log(.info, "Exporting \(compose.images.count) images to \(destURL.path)...")

        Task {
            for image in compose.images {
                let r = await ContainerCLI.exportImage(image, platform: platform, destDir: destURL)
                await MainActor.run {
                    if r.ok {
                        state.log(.ok, "Exported: \(r.image) → \(r.path) (\(String(format: "%.1f", r.sizeMB)) MB)")
                    } else {
                        state.log(.error, "Failed: \(r.image) — \(r.message)")
                    }
                }
            }
            await MainActor.run { state.isExporting = false }
        }
    }

    private func checkConnections() {
        guard let compose = state.composeFile else { return }
        state.validationResults = ComposeParser.checkConnections(compose)
        state.showValidation = true
        let errs = state.validationResults.filter { $0.type == .error }.count
        let warns = state.validationResults.filter { $0.type == .warning }.count
        if errs == 0 && warns == 0 {
            state.log(.ok, "All connections valid")
        } else {
            state.log(.info, "Found: \(errs) errors, \(warns) warnings")
        }
    }

    private func generateEnv() {
        guard let compose = state.composeFile else { return }
        state.sampleEnv = ComposeParser.generateSampleEnv(compose)
        state.showEnv = true
        state.log(.ok, "sample.env generated")
    }

    private func estimateResources() {
        guard let compose = state.composeFile else { return }
        state.resourceEstimate = ComposeParser.estimateResources(compose)
        state.showResources = true
        if let est = state.resourceEstimate {
            state.log(.ok, "Estimated: \(est.totalMemoryMB) MB RAM, \(String(format: "%.1f", est.totalCPUs)) CPUs")
        }
    }

    private func saveEnvFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sample.env"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.sampleEnv.write(to: url, atomically: true, encoding: .utf8)
            state.log(.ok, "Saved: \(url.path)")
        } catch {
            state.log(.error, "Save failed: \(error.localizedDescription)")
        }
    }
}
