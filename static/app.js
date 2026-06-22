const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

let state = {
    loaded: false,
    arch: "arm64",
    pulling: false,
    exporting: false,
    rawYaml: "",
    imagesResolved: [],
};

document.addEventListener("DOMContentLoaded", init);

async function init() {
    setupUpload();
    setupControls();
    checkStatus();
}

async function checkStatus() {
    try {
        const res = await fetch("/api/status");
        const data = await res.json();
        const badge = $("#status-badge");
        if (data.container_available) {
            badge.textContent = "container CLI: ok";
            badge.className = "status-badge ok";
        } else {
            badge.textContent = "container CLI: not found";
            badge.className = "status-badge error";
        }
    } catch {
        const badge = $("#status-badge");
        badge.textContent = "backend: offline";
        badge.className = "status-badge error";
    }
}

function setupUpload() {
    const zone = $("#upload-zone");
    const input = $("#file-input");

    zone.addEventListener("click", () => input.click());

    zone.addEventListener("dragover", (e) => {
        e.preventDefault();
        zone.classList.add("dragover");
    });

    zone.addEventListener("dragleave", () => {
        zone.classList.remove("dragover");
    });

    zone.addEventListener("drop", (e) => {
        e.preventDefault();
        zone.classList.remove("dragover");
        const file = e.dataTransfer.files[0];
        if (file) uploadFile(file);
    });

    input.addEventListener("change", () => {
        if (input.files[0]) uploadFile(input.files[0]);
    });
}

function setupControls() {
    $("#arch-select").addEventListener("change", (e) => {
        state.arch = e.target.value;
    });

    $("#btn-pull").addEventListener("click", pullImages);
    $("#btn-export").addEventListener("click", exportImages);
    $("#btn-check").addEventListener("click", checkConnections);
    $("#btn-env").addEventListener("click", generateEnv);
    $("#btn-resources").addEventListener("click", estimateResources);
    $("#btn-graph").addEventListener("click", showDependencyGraph);
    $("#btn-editor").addEventListener("click", openEditor);
    $("#btn-save-compose").addEventListener("click", saveCompose);
    $("#btn-copy-log").addEventListener("click", copyLog);
    $("#btn-clear-log").addEventListener("click", clearLog);
}

async function uploadFile(file) {
    const formData = new FormData();
    formData.append("file", file);

    log("info", `Loading ${file.name}...`);

    try {
        const res = await fetch("/api/upload", { method: "POST", body: formData });
        const data = await res.json();

        if (data.error) {
            log("error", `Error: ${data.error}`);
            return;
        }

        handleParseResult(data);
    } catch (e) {
        log("error", `Upload failed: ${e.message}`);
    }
}

function handleParseResult(data) {
    state.loaded = true;
    state.rawYaml = data.raw || "";
    state.imagesResolved = data.images_resolved || [];

    log("ok", `Loaded: ${data.service_count} services, ${data.image_count} images`);

    if (state.imagesResolved.length > 0) {
        const remapped = state.imagesResolved.filter((i) => i.original !== i.resolved);
        if (remapped.length > 0) {
            for (const r of remapped) {
                log("info", `Registry: ${r.original} → ${r.resolved}`);
            }
        }
    }

    renderServices(data.services);
    renderImages(data.images, state.imagesResolved);
    renderPorts(data.ports);
    renderDependencies(data.dependencies);
    enableControls();

    // Update editor if open
    const editor = $("#compose-editor");
    if (editor && state.rawYaml) {
        editor.value = state.rawYaml;
    }
}

function renderServices(services) {
    const body = $("#services-body");
    const count = $("#services-count");
    count.textContent = services.length;

    body.innerHTML = services.map((s) => `
        <div class="service-item">
            <div>
                <div class="service-name">${esc(s.name)}</div>
                <div class="service-image">${esc(s.image || "build context")}</div>
            </div>
            <div>
                ${s.ports.map((p) => `<span class="tag">${esc(String(p))}</span>`).join("")}
                ${s.restart ? `<span class="tag">${esc(s.restart)}</span>` : ""}
            </div>
        </div>
    `).join("");

    $("#services-panel").classList.remove("hidden");
}

function renderImages(images, imagesResolved) {
    const body = $("#images-body");
    const count = $("#images-count");
    count.textContent = images.length;

    const resolvedMap = {};
    if (imagesResolved) {
        for (const r of imagesResolved) {
            resolvedMap[r.original] = r.resolved;
        }
    }

    body.innerHTML = images.map((img) => {
        const resolved = resolvedMap[img];
        const isRemapped = resolved && resolved !== img;
        return `
            <div class="service-item">
                <div>
                    <div class="service-name">${esc(img)}</div>
                    ${isRemapped ? `<div class="service-image">→ ${esc(resolved)}</div>` : ""}
                </div>
                ${isRemapped ? `<span class="tag" style="border-color:var(--orange);color:var(--orange)">ghcr.io</span>` : ""}
            </div>
        `;
    }).join("");

    $("#images-panel").classList.remove("hidden");
}

function renderPorts(ports) {
    const body = $("#ports-body");
    const entries = Object.entries(ports);
    const count = $("#ports-count");
    count.textContent = entries.reduce((acc, [, p]) => acc + p.length, 0);

    if (entries.length === 0) {
        body.innerHTML = '<div class="service-item" style="color:var(--text-dim)">No ports exposed</div>';
    } else {
        body.innerHTML = entries.map(([svc, portList]) => `
            <div class="service-item">
                <div class="service-name">${esc(svc)}</div>
                <div>${portList.map((p) => `<span class="tag">${esc(String(p))}</span>`).join("")}</div>
            </div>
        `).join("");
    }
    $("#ports-panel").classList.remove("hidden");
}

function renderDependencies(deps) {
    const body = $("#deps-body");
    const entries = Object.entries(deps);
    const count = $("#deps-count");
    count.textContent = entries.length;

    if (entries.length === 0) {
        body.innerHTML = '<div class="service-item" style="color:var(--text-dim)">No dependencies defined</div>';
    } else {
        body.innerHTML = entries.map(([svc, depList]) => `
            <div class="service-item">
                <div class="service-name">${esc(svc)}</div>
                <div>${depList.map((d) => `<span class="tag">${esc(d)}</span>`).join("")}</div>
            </div>
        `).join("");
    }
    $("#deps-panel").classList.remove("hidden");
}

function enableControls() {
    $$("#controls .btn").forEach((btn) => (btn.disabled = false));
}

// --- Pull ---

async function pullImages() {
    if (state.pulling) return;
    state.pulling = true;
    const btn = $("#btn-pull");
    btn.innerHTML = '<span class="spinner"></span> Pulling...';
    btn.disabled = true;

    log("info", `Pulling images for linux/${state.arch}...`);

    try {
        const res = await fetch("/api/pull", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ architecture: state.arch }),
        });
        const data = await res.json();

        if (data.error) {
            log("error", data.error);
        } else {
            for (const r of data.results) {
                const extra = r.resolved && r.resolved !== r.image ? ` (via ${r.resolved})` : "";
                if (r.ok) {
                    log("ok", `Pulled: ${r.image}${extra}`);
                } else {
                    log("error", `Failed: ${r.image}${extra} — ${r.stderr}`);
                }
            }
        }
    } catch (e) {
        log("error", `Pull failed: ${e.message}`);
    }

    btn.innerHTML = "Pull All";
    btn.disabled = false;
    state.pulling = false;
}

// --- Export ---

async function exportImages() {
    if (state.exporting) return;
    state.exporting = true;
    const btn = $("#btn-export");
    btn.innerHTML = '<span class="spinner"></span> Exporting...';
    btn.disabled = true;

    log("info", `Exporting images as tar.gz for linux/${state.arch}...`);

    try {
        const res = await fetch("/api/export", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ architecture: state.arch }),
        });
        const data = await res.json();

        if (data.error) {
            log("error", data.error);
        } else {
            for (const r of data.results) {
                if (r.ok) {
                    const sizeMB = r.size ? (r.size / 1024 / 1024).toFixed(1) : "?";
                    log("ok", `Exported: ${r.image} → ${r.file} (${sizeMB} MB)`);
                } else {
                    log("error", `Failed: ${r.image} — ${r.stderr}`);
                }
            }
        }
    } catch (e) {
        log("error", `Export failed: ${e.message}`);
    }

    btn.innerHTML = "Export tar.gz";
    btn.disabled = false;
    state.exporting = false;
}

// --- Check ---

async function checkConnections() {
    log("info", "Checking connections...");

    try {
        const res = await fetch("/api/check");
        const data = await res.json();

        if (data.error) {
            log("error", data.error);
            return;
        }

        const body = $("#issues-body");
        body.innerHTML = data.issues.map((i) => `
            <div class="issue-item">
                <div class="issue-dot ${i.type}"></div>
                <div>
                    <span class="issue-svc">${esc(i.service)}</span>
                    ${esc(i.message)}
                </div>
            </div>
        `).join("");
        $("#issues-panel").classList.remove("hidden");

        const errs = data.issues.filter((i) => i.type === "error").length;
        const warns = data.issues.filter((i) => i.type === "warning").length;
        if (errs === 0 && warns === 0) {
            log("ok", "All connections valid");
        } else {
            log("info", `Found: ${errs} errors, ${warns} warnings`);
        }
    } catch (e) {
        log("error", `Check failed: ${e.message}`);
    }
}

// --- Env ---

async function generateEnv() {
    log("info", "Generating sample.env...");

    try {
        const res = await fetch("/api/sample-env");
        const data = await res.json();

        if (data.error) {
            log("error", data.error);
            return;
        }

        const body = $("#env-body");
        body.innerHTML = `
            <div class="env-preview">${esc(data.content)}</div>
            <div style="margin-top:12px;text-align:right">
                <a href="/api/sample-env/download" class="btn" download>Download sample.env</a>
            </div>
        `;
        $("#env-panel").classList.remove("hidden");
        log("ok", "sample.env generated");
    } catch (e) {
        log("error", `Generate failed: ${e.message}`);
    }
}

// --- Resources ---

async function estimateResources() {
    log("info", "Estimating resources...");

    try {
        const res = await fetch("/api/resource-estimate");
        const data = await res.json();

        if (data.error) {
            log("error", data.error);
            return;
        }

        const body = $("#resources-body");
        body.innerHTML = `
            <table class="resource-table">
                <thead>
                    <tr><th>Service</th><th>Memory</th><th>CPUs</th><th>Source</th></tr>
                </thead>
                <tbody>
                    ${data.services.map((s) => `
                        <tr>
                            <td>${esc(s.service)}</td>
                            <td>${s.memory_mb} MB</td>
                            <td>${s.cpus}</td>
                            <td style="color:${s.explicit ? "var(--green)" : "var(--text-dim)"}">${s.explicit ? "explicit" : "default"}</td>
                        </tr>
                    `).join("")}
                    <tr class="total">
                        <td>Total</td>
                        <td>${data.total_memory_mb} MB</td>
                        <td>${data.total_cpus}</td>
                        <td></td>
                    </tr>
                </tbody>
            </table>
        `;
        $("#resources-panel").classList.remove("hidden");
        log("ok", `Estimated: ${data.total_memory_mb} MB RAM, ${data.total_cpus} CPUs`);
    } catch (e) {
        log("error", `Estimate failed: ${e.message}`);
    }
}

// --- Dependency graph ---

async function showDependencyGraph() {
    log("info", "Building dependency graph...");

    try {
        const res = await fetch("/api/dependency-graph");
        const data = await res.json();

        if (data.error) {
            log("error", data.error);
            return;
        }

        const body = $("#graph-body");
        const nodes = data.nodes;
        const edges = data.edges;

        if (nodes.length === 0) {
            body.innerHTML = '<div style="color:var(--text-dim);padding:20px;text-align:center">No services found</div>';
            $("#graph-panel").classList.remove("hidden");
            return;
        }

        const w = 700, h = Math.max(250, nodes.length * 60 + 40);
        const nodeW = 160, nodeH = 36;
        const cols = Math.ceil(Math.sqrt(nodes.length));
        const spacingX = w / (cols + 1);
        const spacingY = h / (Math.ceil(nodes.length / cols) + 1);

        const positions = {};
        nodes.forEach((n, i) => {
            const col = i % cols;
            const row = Math.floor(i / cols);
            positions[n.id] = {
                x: spacingX * (col + 1),
                y: spacingY * (row + 1),
            };
        });

        let svg = `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" xmlns="http://www.w3.org/2000/svg">`;
        svg += `<defs><marker id="arrowhead" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">`;
        svg += `<polygon points="0 0, 8 3, 0 6" fill="var(--text-dim)"/></marker></defs>`;

        for (const edge of edges) {
            const from = positions[edge.from];
            const to = positions[edge.to];
            if (from && to) {
                svg += `<line x1="${from.x}" y1="${from.y}" x2="${to.x}" y2="${to.y}" class="dep-edge"/>`;
            }
        }

        for (const node of nodes) {
            const pos = positions[node.id];
            svg += `<rect x="${pos.x - nodeW / 2}" y="${pos.y - nodeH / 2}" width="${nodeW}" height="${nodeH}" class="dep-node"/>`;
            svg += `<text x="${pos.x}" y="${pos.y}" class="dep-label">${esc(node.id)}</text>`;
        }

        svg += `</svg>`;
        body.innerHTML = `<div class="dep-graph">${svg}</div>`;
        $("#graph-panel").classList.remove("hidden");
        log("ok", `Graph: ${nodes.length} nodes, ${edges.length} edges`);
    } catch (e) {
        log("error", `Graph failed: ${e.message}`);
    }
}

// --- Compose editor ---

function openEditor() {
    const panel = $("#editor-panel");
    const editor = $("#compose-editor");

    if (!panel.classList.contains("hidden")) {
        panel.classList.add("hidden");
        return;
    }

    editor.value = state.rawYaml;
    panel.classList.remove("hidden");
    editor.focus();
}

async function saveCompose() {
    const editor = $("#compose-editor");
    const content = editor.value;

    if (!content.trim()) {
        log("error", "Editor is empty");
        return;
    }

    log("info", "Saving and re-parsing compose...");

    try {
        const res = await fetch("/api/compose/save", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ content }),
        });
        const data = await res.json();

        if (data.error) {
            log("error", `Save error: ${data.error}`);
            return;
        }

        handleParseResult(data);
        log("ok", "Compose saved and re-parsed");
    } catch (e) {
        log("error", `Save failed: ${e.message}`);
    }
}

// --- Log ---

function log(type, message) {
    const logBody = $("#log-body");
    const line = document.createElement("div");
    line.className = `log-line ${type}`;
    const time = new Date().toLocaleTimeString();
    line.textContent = `[${time}] ${message}`;
    logBody.appendChild(line);
    logBody.scrollTop = logBody.scrollHeight;
    $("#log-area").classList.remove("hidden");
}

function copyLog() {
    const logBody = $("#log-body");
    const text = Array.from(logBody.children)
        .map((el) => el.textContent)
        .join("\n");
    navigator.clipboard.writeText(text).then(() => {
        log("ok", "Log copied to clipboard");
    }).catch(() => {
        // Fallback: select text manually
        const range = document.createRange();
        range.selectNodeContents(logBody);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        log("info", "Log selected — use Cmd+C to copy");
    });
}

function clearLog() {
    $("#log-body").innerHTML = "";
}

function esc(str) {
    const el = document.createElement("span");
    el.textContent = str;
    return el.innerHTML;
}
