import yaml
import re
from pathlib import Path


def parse_compose(content: str) -> dict:
    data = yaml.safe_load(content)
    if not isinstance(data, dict):
        raise ValueError("Invalid docker-compose format")
    return data


def extract_services(data: dict) -> dict:
    return data.get("services", {})


def resolve_image_registry(image: str) -> str:
    """Resolve image to full registry path.
    - No '/' → Docker Hub official (unchanged)
    - One '/' and first part has no '.' → ghcr.io prefix
    - Already has registry (first part contains '.') → as-is
    """
    parts = image.split("/")
    if len(parts) == 1:
        return image
    if len(parts) == 2 and "." not in parts[0]:
        return f"ghcr.io/{image}"
    return image


def extract_images(data: dict) -> list[str]:
    images = []
    for name, svc in extract_services(data).items():
        img = svc.get("image")
        if img:
            images.append(img)
    return sorted(set(images))


def extract_images_resolved(data: dict) -> list[dict]:
    images = []
    seen = set()
    for name, svc in extract_services(data).items():
        img = svc.get("image")
        if img and img not in seen:
            seen.add(img)
            images.append({
                "original": img,
                "resolved": resolve_image_registry(img),
            })
    return sorted(images, key=lambda x: x["original"])


def extract_env_vars(data: dict) -> dict[str, list[str]]:
    result = {}
    for name, svc in extract_services(data).items():
        env = svc.get("environment", {})
        vars_list = []
        if isinstance(env, list):
            for item in env:
                vars_list.append(item.split("=", 1)[0] if "=" in item else item)
        elif isinstance(env, dict):
            vars_list = list(env.keys())
        env_file = svc.get("env_file")
        if env_file:
            if isinstance(env_file, str):
                vars_list.append(f"# from {env_file}")
            elif isinstance(env_file, list):
                for f in env_file:
                    vars_list.append(f"# from {f}")
        if vars_list:
            result[name] = vars_list
    return result


def generate_sample_env(data: dict) -> str:
    lines = ["# Auto-generated sample.env", "# Fill in the values for your deployment", ""]
    env_vars = extract_env_vars(data)
    seen = set()
    for svc_name, vars_list in sorted(env_vars.items()):
        lines.append(f"# === {svc_name} ===")
        for var in vars_list:
            if var.startswith("#"):
                lines.append(var)
                continue
            if var not in seen:
                seen.add(var)
                lines.append(f"{var}=")
        lines.append("")
    return "\n".join(lines)


def extract_networks(data: dict) -> dict:
    return data.get("networks", {})


def extract_volumes(data: dict) -> dict:
    return data.get("volumes", {})


def extract_ports(data: dict) -> dict[str, list[str]]:
    result = {}
    for name, svc in extract_services(data).items():
        ports = svc.get("ports", [])
        if ports:
            result[name] = [str(p) for p in ports]
    return result


def extract_dependencies(data: dict) -> dict[str, list[str]]:
    result = {}
    for name, svc in extract_services(data).items():
        deps = []
        depends = svc.get("depends_on", [])
        if isinstance(depends, list):
            deps.extend(depends)
        elif isinstance(depends, dict):
            deps.extend(depends.keys())
        links = svc.get("links", [])
        if links:
            deps.extend([l.split(":")[0] for l in links])
        if deps:
            result[name] = sorted(set(deps))
    return result


def check_connections(data: dict) -> list[dict]:
    issues = []
    services = extract_services(data)
    service_names = set(services.keys())

    for name, svc in services.items():
        depends = svc.get("depends_on", [])
        dep_names = depends if isinstance(depends, list) else list(depends.keys())
        for dep in dep_names:
            if dep not in service_names:
                issues.append({
                    "type": "error",
                    "service": name,
                    "message": f"depends_on '{dep}' — service not found",
                })

        links = svc.get("links", [])
        for link in links:
            target = link.split(":")[0]
            if target not in service_names:
                issues.append({
                    "type": "error",
                    "service": name,
                    "message": f"link '{target}' — service not found",
                })

        if not svc.get("image") and not svc.get("build"):
            issues.append({
                "type": "error",
                "service": name,
                "message": "no 'image' or 'build' specified",
            })

    all_ports = extract_ports(data)
    host_ports = {}
    for svc_name, ports in all_ports.items():
        for p in ports:
            p_str = str(p)
            match = re.match(r"(?:\d+\.\d+\.\d+\.\d+:)?(\d+):\d+", p_str)
            if match:
                hp = match.group(1)
                if hp in host_ports:
                    issues.append({
                        "type": "warning",
                        "service": svc_name,
                        "message": f"host port {hp} conflicts with service '{host_ports[hp]}'",
                    })
                else:
                    host_ports[hp] = svc_name

    networks = extract_networks(data)
    network_names = set(networks.keys()) if networks else set()
    for name, svc in services.items():
        svc_nets = svc.get("networks")
        if svc_nets:
            net_list = svc_nets if isinstance(svc_nets, list) else list(svc_nets.keys())
            for net in net_list:
                if net != "default" and networks and net not in network_names:
                    issues.append({
                        "type": "warning",
                        "service": name,
                        "message": f"network '{net}' not defined in top-level networks",
                    })

    volumes = extract_volumes(data)
    volume_names = set(volumes.keys()) if volumes else set()
    for name, svc in services.items():
        svc_vols = svc.get("volumes", [])
        for v in svc_vols:
            if isinstance(v, str) and ":" in v:
                src = v.split(":")[0]
                if not src.startswith((".", "/", "~", "$")):
                    if volumes and src not in volume_names:
                        issues.append({
                            "type": "warning",
                            "service": name,
                            "message": f"named volume '{src}' not defined in top-level volumes",
                        })

    if not issues:
        issues.append({
            "type": "ok",
            "service": "-",
            "message": "All connections and references look valid",
        })
    return issues


def get_service_summary(data: dict) -> list[dict]:
    summary = []
    for name, svc in extract_services(data).items():
        summary.append({
            "name": name,
            "image": svc.get("image", ""),
            "build": bool(svc.get("build")),
            "ports": svc.get("ports", []),
            "depends_on": svc.get("depends_on", []),
            "restart": svc.get("restart", ""),
            "networks": svc.get("networks", []),
        })
    return summary
