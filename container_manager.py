import subprocess
import shutil
import json
import os
import re
from pathlib import Path

CONTAINER_BIN = shutil.which("container") or "container"
UPLOAD_DIR = Path(__file__).parent / "uploads"
EXPORT_DIR = Path(__file__).parent / "exports"
EXPORT_DIR.mkdir(exist_ok=True)

KNOWN_ARCHITECTURES = ["arm64", "amd64"]


def run_cmd(args: list[str], timeout: int = 300) -> dict:
    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "ok": proc.returncode == 0,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
            "code": proc.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "stdout": "", "stderr": "Command timed out", "code": -1}
    except FileNotFoundError:
        return {"ok": False, "stdout": "", "stderr": f"Command not found: {args[0]}", "code": -1}


def container_available() -> bool:
    result = run_cmd([CONTAINER_BIN, "version"])
    return result["ok"]


def pull_image(image: str, platform: str = "linux/arm64") -> dict:
    args = [CONTAINER_BIN, "pull", "--platform", platform, image]
    return run_cmd(args, timeout=600)


def pull_all_images(images: list[dict], platform: str = "linux/arm64") -> list[dict]:
    """Pull images. Each item: {"original": ..., "resolved": ...}"""
    results = []
    for img_info in images:
        if isinstance(img_info, str):
            original = resolved = img_info
        else:
            original = img_info["original"]
            resolved = img_info["resolved"]
        result = pull_image(resolved, platform)
        results.append({"image": original, "resolved": resolved, **result})
    return results


def save_image(image: str, output_path: str) -> dict:
    args = [CONTAINER_BIN, "image", "save", "-o", output_path, image]
    return run_cmd(args, timeout=600)


def export_all_images(images: list[dict], platform: str = "linux/arm64", dest_dir: str | None = None) -> list[dict]:
    """Export images. Each item: {"original": ..., "resolved": ...}"""
    dest = Path(dest_dir) if dest_dir else EXPORT_DIR
    dest.mkdir(parents=True, exist_ok=True)
    results = []
    for img_info in images:
        if isinstance(img_info, str):
            original = resolved = img_info
        else:
            original = img_info["original"]
            resolved = img_info["resolved"]
        safe_name = re.sub(r"[/:@]", "_", original)
        arch_suffix = platform.replace("/", "_")
        tar_path = dest / f"{safe_name}_{arch_suffix}.tar"
        gz_path = dest / f"{safe_name}_{arch_suffix}.tar.gz"

        result = save_image(resolved, str(tar_path))
        if result["ok"] and tar_path.exists():
            compress = run_cmd(["gzip", "-f", str(tar_path)])
            if compress["ok"] and gz_path.exists():
                result["file"] = str(gz_path)
                result["size"] = gz_path.stat().st_size
            else:
                result["file"] = str(tar_path)
                if tar_path.exists():
                    result["size"] = tar_path.stat().st_size
        results.append({"image": original, "resolved": resolved, **result})
    return results


def list_images() -> dict:
    return run_cmd([CONTAINER_BIN, "image", "list"])


def inspect_image(image: str) -> dict:
    return run_cmd([CONTAINER_BIN, "image", "inspect", image])


def system_status() -> dict:
    result = run_cmd([CONTAINER_BIN, "system", "info"])
    if not result["ok"]:
        result = run_cmd([CONTAINER_BIN, "version"])
    return result


def get_available_architectures() -> list[str]:
    return KNOWN_ARCHITECTURES
