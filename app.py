import json
import os
from pathlib import Path

from flask import Flask, render_template, request, jsonify, send_file

import compose_parser as parser
import container_manager as cm

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024

UPLOAD_DIR = Path(__file__).parent / "uploads"
UPLOAD_DIR.mkdir(exist_ok=True)

current_compose: dict | None = None
current_compose_raw: str = ""


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def api_status():
    available = cm.container_available()
    info = cm.system_status()
    return jsonify({
        "container_available": available,
        "info": info.get("stdout", ""),
        "architectures": cm.get_available_architectures(),
    })


@app.route("/api/upload", methods=["POST"])
def api_upload():
    global current_compose, current_compose_raw

    if "file" in request.files:
        f = request.files["file"]
        if not f.filename:
            return jsonify({"error": "No file selected"}), 400
        content = f.read().decode("utf-8")
    elif request.is_json:
        content = request.json.get("content", "")
    else:
        return jsonify({"error": "No file or content provided"}), 400

    try:
        data = parser.parse_compose(content)
    except Exception as e:
        return jsonify({"error": f"Parse error: {e}"}), 400

    current_compose = data
    current_compose_raw = content

    save_path = UPLOAD_DIR / "docker-compose.yaml"
    save_path.write_text(content)

    services = parser.get_service_summary(data)
    images = parser.extract_images(data)
    networks = parser.extract_networks(data)
    volumes = parser.extract_volumes(data)
    ports = parser.extract_ports(data)
    deps = parser.extract_dependencies(data)

    images_resolved = parser.extract_images_resolved(data)

    return jsonify({
        "ok": True,
        "raw": content,
        "services": services,
        "images": images,
        "images_resolved": images_resolved,
        "networks": networks,
        "volumes": volumes,
        "ports": ports,
        "dependencies": deps,
        "service_count": len(services),
        "image_count": len(images),
    })


@app.route("/api/pull", methods=["POST"])
def api_pull():
    if not current_compose:
        return jsonify({"error": "No compose file loaded"}), 400

    body = request.json or {}
    arch = body.get("architecture", "arm64")
    platform = f"linux/{arch}"
    images = parser.extract_images_resolved(current_compose)

    if not images:
        return jsonify({"error": "No images found in compose file"}), 400

    results = cm.pull_all_images(images, platform)
    return jsonify({"ok": True, "results": results, "platform": platform})


@app.route("/api/export", methods=["POST"])
def api_export():
    if not current_compose:
        return jsonify({"error": "No compose file loaded"}), 400

    body = request.json or {}
    arch = body.get("architecture", "arm64")
    platform = f"linux/{arch}"
    images = parser.extract_images_resolved(current_compose)

    if not images:
        return jsonify({"error": "No images found in compose file"}), 400

    results = cm.export_all_images(images, platform)
    return jsonify({"ok": True, "results": results, "platform": platform})


@app.route("/api/check", methods=["GET"])
def api_check():
    if not current_compose:
        return jsonify({"error": "No compose file loaded"}), 400

    issues = parser.check_connections(current_compose)
    return jsonify({"ok": True, "issues": issues})


@app.route("/api/sample-env", methods=["GET"])
def api_sample_env():
    if not current_compose:
        return jsonify({"error": "No compose file loaded"}), 400

    content = parser.generate_sample_env(current_compose)
    return jsonify({"ok": True, "content": content})


@app.route("/api/sample-env/download", methods=["GET"])
def download_sample_env():
    if not current_compose:
        return jsonify({"error": "No compose file loaded"}), 400

    content = parser.generate_sample_env(current_compose)
    env_path = UPLOAD_DIR / "sample.env"
    env_path.write_text(content)
    return send_file(env_path, as_attachment=True, download_name="sample.env")


@app.route("/api/compose/raw", methods=["GET"])
def api_compose_raw():
    if not current_compose_raw:
        return jsonify({"error": "No compose file loaded"}), 400
    return jsonify({"ok": True, "content": current_compose_raw})


@app.route("/api/compose/save", methods=["POST"])
def api_compose_save():
    global current_compose, current_compose_raw

    body = request.json or {}
    content = body.get("content", "")
    if not content.strip():
        return jsonify({"error": "Empty content"}), 400

    try:
        data = parser.parse_compose(content)
    except Exception as e:
        return jsonify({"error": f"Parse error: {e}"}), 400

    current_compose = data
    current_compose_raw = content

    save_path = UPLOAD_DIR / "docker-compose.yaml"
    save_path.write_text(content)

    services = parser.get_service_summary(data)
    images = parser.extract_images(data)
    images_resolved = parser.extract_images_resolved(data)
    networks = parser.extract_networks(data)
    volumes = parser.extract_volumes(data)
    ports = parser.extract_ports(data)
    deps = parser.extract_dependencies(data)

    return jsonify({
        "ok": True,
        "raw": content,
        "services": services,
        "images": images,
        "images_resolved": images_resolved,
        "networks": networks,
        "volumes": volumes,
        "ports": ports,
        "dependencies": deps,
        "service_count": len(services),
        "image_count": len(images),
    })


@app.route("/api/compose/download", methods=["GET"])
def api_compose_download():
    if not current_compose_raw:
        return jsonify({"error": "No compose file loaded"}), 400
    save_path = UPLOAD_DIR / "docker-compose.yaml"
    save_path.write_text(current_compose_raw)
    return send_file(save_path, as_attachment=True, download_name="docker-compose.yaml")


@app.route("/api/images", methods=["GET"])
def api_images():
    result = cm.list_images()
    return jsonify(result)


@app.route("/api/dependency-graph", methods=["GET"])
def api_dependency_graph():
    if not current_compose:
        return jsonify({"error": "No compose file loaded"}), 400

    services = parser.extract_services(current_compose)
    deps = parser.extract_dependencies(current_compose)
    ports = parser.extract_ports(current_compose)

    nodes = []
    edges = []
    for name in services:
        svc = services[name]
        nodes.append({
            "id": name,
            "image": svc.get("image", "build"),
            "ports": ports.get(name, []),
        })

    for svc, dep_list in deps.items():
        for dep in dep_list:
            edges.append({"from": svc, "to": dep})

    return jsonify({"ok": True, "nodes": nodes, "edges": edges})


@app.route("/api/resource-estimate", methods=["GET"])
def api_resource_estimate():
    if not current_compose:
        return jsonify({"error": "No compose file loaded"}), 400

    services = parser.extract_services(current_compose)
    estimates = []
    total_mem = 0
    total_cpu = 0.0

    for name, svc in services.items():
        deploy = svc.get("deploy", {})
        resources = deploy.get("resources", {})
        limits = resources.get("limits", {})
        reservations = resources.get("reservations", {})

        mem = limits.get("memory") or reservations.get("memory") or "256M"
        cpus = limits.get("cpus") or reservations.get("cpus") or "0.5"

        mem_val = _parse_memory(str(mem))
        cpu_val = float(cpus)

        total_mem += mem_val
        total_cpu += cpu_val

        estimates.append({
            "service": name,
            "memory_mb": mem_val,
            "cpus": cpu_val,
            "explicit": bool(limits or reservations),
        })

    return jsonify({
        "ok": True,
        "services": estimates,
        "total_memory_mb": total_mem,
        "total_cpus": total_cpu,
    })


def _parse_memory(val: str) -> int:
    val = val.strip().upper()
    multipliers = {"K": 1 / 1024, "M": 1, "G": 1024, "T": 1024 * 1024}
    for suffix, mult in multipliers.items():
        if val.endswith(suffix) or val.endswith(suffix + "B"):
            num = val.rstrip("B").rstrip(suffix)
            try:
                return int(float(num) * mult)
            except ValueError:
                return 256
    try:
        return int(int(val) / (1024 * 1024))
    except ValueError:
        return 256


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5150, debug=True)
