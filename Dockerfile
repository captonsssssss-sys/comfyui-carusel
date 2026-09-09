# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

# ============================================================
# 1. CHECK BASE IMAGE
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -f "${COMFYUI_PATH}/main.py"; \
    python3 --version; \
    python3 -m pip --version


# ============================================================
# 2. UPDATE PIP TOOLS
# ============================================================

RUN set -eux; \
    python3 -m pip install --upgrade \
        pip \
        setuptools \
        wheel \
        packaging


# ============================================================
# 3. INSTALL COMFYUI-LLAMA-CPP-VLM
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}/custom_nodes"; \
    rm -rf ComfyUI-llama-cpp_vlm; \
    git clone --depth 1 \
        https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm.git \
        ComfyUI-llama-cpp_vlm; \
    test -f ComfyUI-llama-cpp_vlm/nodes.py; \
    test -d ComfyUI-llama-cpp_vlm/support


# ============================================================
# 4. INSTALL NODE REQUIREMENTS
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f requirements.txt ]; then \
        python3 -m pip install -r requirements.txt; \
    fi


# ============================================================
# 5. BASIC PYTHON DEPENDENCIES
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 6. INSTALL LLAMA-CPP-PYTHON
#
# We use JamePeng prebuilt wheels.
# No source compilation.
# No apt/apk/dnf.
#
# The script:
#   - detects Python ABI
#   - detects compatible platform tags
#   - checks JamePeng releases
#   - finds a compatible wheel
#   - prefers CUDA wheels
#   - downloads the wheel
#   - installs it locally
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json
import os
import platform
import sys
import urllib.request
import urllib.error
import subprocess
import tempfile

from packaging.tags import sys_tags
from packaging.utils import parse_wheel_filename


API_URL = (
    "https://api.github.com/repos/"
    "JamePeng/llama-cpp-python/releases"
    "?per_page=100"
)

print("=" * 80)
print("Searching JamePeng llama-cpp-python wheels")
print("=" * 80)

print("Python:", sys.version)
print("Platform:", platform.platform())
print("Machine:", platform.machine())

compatible_tags = set(sys_tags())

print("Compatible Python/platform tags:")
for tag in list(compatible_tags)[:20]:
    print("  ", tag)

print("=" * 80)
print("Requesting GitHub releases...")
print(API_URL)
print("=" * 80)

request = urllib.request.Request(
    API_URL,
    headers={
        "User-Agent": "ComfyUI-Docker-Build",
        "Accept": "application/vnd.github+json",
    },
)

try:
    with urllib.request.urlopen(request, timeout=60) as response:
        status = response.status
        raw = response.read()

except urllib.error.HTTPError as exc:
    print("GitHub API HTTP ERROR:", exc.code)
    print(exc.read().decode("utf-8", errors="replace"))
    raise

except Exception as exc:
    print("GitHub API ERROR:", repr(exc))
    raise

print("GitHub API status:", status)

releases = json.loads(raw)

if not isinstance(releases, list):
    print("Unexpected GitHub API response:")
    print(releases)
    raise RuntimeError("GitHub releases API returned unexpected data")


# ------------------------------------------------------------
# Collect wheels
# ------------------------------------------------------------

candidates = []

for release in releases:
    release_name = release.get("name") or release.get("tag_name") or "unknown"

    for asset in release.get("assets", []):
        asset_name = asset.get("name", "")
        asset_url = asset.get("browser_download_url")

        if not asset_name.endswith(".whl"):
            continue

        try:
            distribution, version, build, tags = parse_wheel_filename(
                asset_name
            )
        except Exception as exc:
            print(
                "Skipping unparseable wheel:",
                asset_name,
                "reason:",
                repr(exc),
            )
            continue

        wheel_tags = set(tags)
        matching_tags = wheel_tags.intersection(compatible_tags)

        if not matching_tags:
            continue

        lower_name = asset_name.lower()

        # Prefer CUDA builds.
        cuda_score = 0

        if "cuda" in lower_name:
            cuda_score += 100

        if "cu12" in lower_name:
            cuda_score += 50

        if "cu11" in lower_name:
            cuda_score += 40

        # Prefer Linux x86_64.
        platform_score = 0

        if "linux" in lower_name:
            platform_score += 20

        if "x86_64" in lower_name or "amd64" in lower_name:
            platform_score += 20

        # Prefer newer releases in the API order.
        release_score = len(releases) - releases.index(release)

        score = (
            cuda_score
            + platform_score
            + release_score
        )

        candidates.append(
            {
                "score": score,
                "release": release_name,
                "name": asset_name,
                "url": asset_url,
                "tags": [str(x) for x in matching_tags],
            }
        )


print("=" * 80)
print("Compatible wheels found:", len(candidates))
print("=" * 80)

if not candidates:
    print("NO COMPATIBLE LLAMA-CPP-PYTHON WHEEL FOUND.")
    print()
    print("Python:", sys.version)
    print("Machine:", platform.machine())
    print()
    print("Available wheel assets from JamePeng:")

    for release in releases:
        release_name = (
            release.get("name")
            or release.get("tag_name")
            or "unknown"
        )

        print()
        print("RELEASE:", release_name)

        for asset in release.get("assets", []):
            name = asset.get("name", "")

            if name.endswith(".whl"):
                print("  ", name)

    raise RuntimeError(
        "JamePeng does not provide a compatible "
        "llama-cpp-python wheel for this Python/platform."
    )


# ------------------------------------------------------------
# Sort candidates
# ------------------------------------------------------------

candidates.sort(
    key=lambda item: item["score"],
    reverse=True,
)

print("Top compatible wheels:")

for candidate in candidates[:10]:
    print(
        candidate["score"],
        candidate["release"],
        candidate["name"],
    )

selected = candidates[0]

print("=" * 80)
print("SELECTED WHEEL")
print("=" * 80)
print("Release:", selected["release"])
print("File:", selected["name"])
print("URL:", selected["url"])
print("Matching tags:", selected["tags"])
print("=" * 80)


# ------------------------------------------------------------
# Download
# ------------------------------------------------------------

wheel_path = os.path.join(
    tempfile.gettempdir(),
    selected["name"],
)

print("Downloading wheel to:")
print(wheel_path)

download_request = urllib.request.Request(
    selected["url"],
    headers={
        "User-Agent": "ComfyUI-Docker-Build",
        "Accept": "application/octet-stream",
    },
)

try:
    with urllib.request.urlopen(
        download_request,
        timeout=300,
    ) as response:
        with open(wheel_path, "wb") as output:
            while True:
                chunk = response.read(1024 * 1024)

                if not chunk:
                    break

                output.write(chunk)

except Exception as exc:
    print("Wheel download failed:", repr(exc))
    raise

print("Wheel downloaded successfully.")


# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

subprocess.check_call(
    [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--no-cache-dir",
        "--force-reinstall",
        wheel_path,
    ]
)

print("=" * 80)
print("llama-cpp-python installation finished")
print("=" * 80)
PY


# ============================================================
# 7. VERIFY LLAMA-CPP
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import sys
import llama_cpp

print("=" * 80)
print("llama_cpp import: OK")
print("Python:", sys.version)
print("llama_cpp version:", getattr(llama_cpp, "__version__", "unknown"))
print("llama_cpp path:", llama_cpp.__file__)
print("=" * 80)

from llama_cpp import Llama

print("Llama class: OK")

from llama_cpp.llama_chat_format import (
    Llava15ChatHandler,
    Llava16ChatHandler,
    MoondreamChatHandler,
    NanoLlavaChatHandler,
    Llama3VisionAlphaChatHandler,
    MiniCPMv26ChatHandler,
)

print("Standard vision chat handlers: OK")

try:
    from llama_cpp.llama_chat_format import Qwen35ChatHandler
    print("Qwen35ChatHandler: OK")
except ImportError as exc:
    print("=" * 80)
    print("WARNING: Qwen35ChatHandler is NOT available")
    print(repr(exc))
    print("=" * 80)
    raise
PY


# ============================================================
# 8. VERIFY CUSTOM NODE AS A PACKAGE
#
# IMPORTANT:
# Do NOT load nodes.py as a standalone file.
#
# nodes.py contains relative imports:
#
#   from .support.cqdm import cqdm
#   from .support.gguf_layers import ...
#
# Therefore it must be imported as a package.
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}"; \
    python3 - <<'PY'
import importlib
import os
import sys
import traceback

custom_nodes_dir = (
    "/default-comfyui-bundle/ComfyUI/custom_nodes"
)

package_dir = (
    "/default-comfyui-bundle/ComfyUI/"
    "custom_nodes/ComfyUI-llama-cpp_vlm"
)

print("=" * 80)
print("Testing ComfyUI-llama-cpp_vlm")
print("=" * 80)

print("Package directory:", package_dir)
print("Exists:", os.path.isdir(package_dir))
print("nodes.py exists:", os.path.isfile(
    os.path.join(package_dir, "nodes.py")
))
print("support exists:", os.path.isdir(
    os.path.join(package_dir, "support")
))

if custom_nodes_dir not in sys.path:
    sys.path.insert(0, custom_nodes_dir)

print("custom_nodes added to sys.path")

try:
    module = importlib.import_module(
        "ComfyUI-llama-cpp_vlm.nodes"
    )

    print("=" * 80)
    print("ComfyUI-llama-cpp_vlm import: OK")
    print("=" * 80)

    mappings = getattr(
        module,
        "NODE_CLASS_MAPPINGS",
        None,
    )

    if mappings is None:
        raise RuntimeError(
            "NODE_CLASS_MAPPINGS was not found"
        )

    print(
        "Registered node classes:",
        len(mappings),
    )

    required_nodes = [
        "llama_cpp_model_loader",
        "llama_cpp_instruct_adv",
        "llama_cpp_parameters",
        "llama_cpp_unload_model",
        "llama_cpp_clean_states",
        "parse_json_node",
        "json_to_bbox",
        "bbox_to_segs",
        "bbox_to_mask",
        "bboxes_to_bbox",
        "remove_code_block",
        "PromptEnhancerPreset",
        "llama_cpp_text_encoder",
    ]

    print("=" * 80)
    print("Checking required Llama nodes")
    print("=" * 80)

    for node_name in required_nodes:
        if node_name not in mappings:
            raise RuntimeError(
                f"Required node missing: {node_name}"
            )

        print("OK:", node_name)

    print("=" * 80)
    print("ALL LLAMA CUSTOM NODES: OK")
    print("=" * 80)

except Exception:
    print("=" * 80)
    print("FAILED TO IMPORT ComfyUI-llama-cpp_vlm")
    print("=" * 80)
    traceback.print_exc()
    raise
PY


# ============================================================
# 9. CREATE LLM MODEL DIRECTORY
# ============================================================

RUN set -eux; \
    mkdir -p "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p "${COMFYUI_PATH}/workflows"; \
    chmod -R 777 "${COMFYUI_PATH}/models/LLM" || true; \
    chmod -R 777 "${COMFYUI_PATH}/workflows" || true


# ============================================================
# 10. VALIDATE WORKFLOW
# ============================================================

COPY CARUSEL.json /tmp/CARUSEL.json

RUN set -eux; \
    python3 - <<'PY'
import json

workflow_file = "/tmp/CARUSEL.json"

print("=" * 80)
print("Validating CARUSEL.json")
print("=" * 80)

with open(
    workflow_file,
    "r",
    encoding="utf-8",
) as f:
    workflow = json.load(f)

print("JSON: OK")

required_types = {
    "llama_cpp_parameters",
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
}

found_types = set()

for node_id, node in workflow.items():
    if not isinstance(node, dict):
        continue

    node_type = node.get("class_type")

    if node_type:
        found_types.add(node_type)

print("Workflow nodes:", len(workflow))

for required in sorted(required_types):
    if required in found_types:
        print("FOUND:", required)
    else:
        raise RuntimeError(
            f"Required workflow node missing: {required}"
        )

print("=" * 80)
print("CARUSEL.json validation: OK")
print("=" * 80)
PY


# ============================================================
# 11. COPY WORKFLOW INTO IMAGE
# ============================================================

RUN set -eux; \
    cp /tmp/CARUSEL.json \
    "${COMFYUI_PATH}/workflows/CARUSEL.json"; \
    rm -f /tmp/CARUSEL.json


# ============================================================
# 12. FINAL ENVIRONMENT CHECK
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}"; \
    python3 - <<'PY'
import os
import sys

print("=" * 80)
print("FINAL DOCKER CHECK")
print("=" * 80)

print("Python:", sys.version)
print("ComfyUI:", os.path.isdir(
    "/default-comfyui-bundle/ComfyUI"
))

print("Llama custom node:", os.path.isdir(
    "/default-comfyui-bundle/ComfyUI/custom_nodes/"
    "ComfyUI-llama-cpp_vlm"
))

print("LLM directory:", os.path.isdir(
    "/default-comfyui-bundle/ComfyUI/models/LLM"
))

print("Workflow:", os.path.isfile(
    "/default-comfyui-bundle/ComfyUI/workflows/CARUSEL.json"
))

import llama_cpp

print(
    "llama_cpp:",
    getattr(llama_cpp, "__version__", "unknown")
)

print("=" * 80)
print("DOCKER IMAGE CHECK: OK")
print("=" * 80)
PY


# ============================================================
# 13. DEFAULT WORKDIR
# ============================================================

WORKDIR ${COMFYUI_PATH}
