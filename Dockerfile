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
    echo "=========================================="; \
    echo "Checking base image"; \
    echo "=========================================="; \
    echo "ComfyUI: ${COMFYUI_PATH}"; \
    echo ""; \
    python3 --version; \
    python3 -m pip --version; \
    echo ""; \
    echo "Python executable:"; \
    command -v python3; \
    echo ""; \
    echo "CUDA:"; \
    if command -v nvcc >/dev/null 2>&1; then \
        nvcc --version; \
    else \
        echo "nvcc not found - using prebuilt llama-cpp wheel"; \
    fi; \
    echo ""; \
    echo "Base image check complete"


# ============================================================
# 2. CHECK COMFYUI
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -d "${COMFYUI_PATH}/models"; \
    test -d "${COMFYUI_PATH}/custom_nodes"; \
    echo "ComfyUI found at: ${COMFYUI_PATH}"


# ============================================================
# 3. UPDATE PYTHON PACKAGING TOOLS
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        --upgrade \
        pip \
        setuptools \
        wheel \
        packaging


# ============================================================
# 4. INSTALL COMFYUI-LLAMA-CPP-VLM
#
# Repository:
# https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm
#
# Download directly from GitHub.
# No apt.
# No apk.
# No dnf.
# No git.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import os
import shutil
import urllib.request
import zipfile

COMFYUI = "/default-comfyui-bundle/ComfyUI"

NODE = os.path.join(
    COMFYUI,
    "custom_nodes",
    "ComfyUI-llama-cpp_vlm"
)

ZIP = "/tmp/llama-cpp-vlm.zip"
TMP = "/tmp/llama-cpp-vlm"

URL = (
    "https://github.com/"
    "lihaoyun6/ComfyUI-llama-cpp_vlm/"
    "archive/refs/heads/main.zip"
)

print("Downloading ComfyUI-llama-cpp_vlm...")
urllib.request.urlretrieve(URL, ZIP)

if os.path.exists(TMP):
    shutil.rmtree(TMP)

if os.path.exists(NODE):
    shutil.rmtree(NODE)

os.makedirs(TMP, exist_ok=True)

print("Extracting...")

with zipfile.ZipFile(ZIP, "r") as archive:
    archive.extractall(TMP)

dirs = [
    os.path.join(TMP, x)
    for x in os.listdir(TMP)
    if os.path.isdir(os.path.join(TMP, x))
]

if not dirs:
    raise RuntimeError(
        "Could not find extracted repository"
    )

shutil.move(dirs[0], NODE)

os.remove(ZIP)
shutil.rmtree(TMP, ignore_errors=True)

if not os.path.isfile(
    os.path.join(NODE, "nodes.py")
):
    raise RuntimeError(
        "ComfyUI-llama-cpp_vlm nodes.py not found"
    )

print("ComfyUI-llama-cpp_vlm installed")
print(NODE)
PY


# ============================================================
# 5. VERIFY LLAMA NODE FILES
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -f "${NODE_PATH}/nodes.py"; \
    grep -q "llama_cpp_model_loader" "${NODE_PATH}/nodes.py"; \
    grep -q "llama_cpp_instruct_adv" "${NODE_PATH}/nodes.py"; \
    grep -q "llama_cpp_parameters" "${NODE_PATH}/nodes.py"; \
    grep -q "llama_cpp_unload_model" "${NODE_PATH}/nodes.py"; \
    grep -q "llama_cpp_clean_states" "${NODE_PATH}/nodes.py"; \
    grep -q "llama_cpp_text_encoder" "${NODE_PATH}/nodes.py"; \
    echo "Required llama nodes found"


# ============================================================
# 6. INSTALL LLAMA NODE REQUIREMENTS
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f "${NODE_PATH}/requirements.txt" ]; then \
        python3 -m pip install \
            -r "${NODE_PATH}/requirements.txt"; \
    fi


# ============================================================
# 7. GENERAL PYTHON DEPENDENCIES
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 8. REMOVE OLD LLAMA-CPP-PYTHON
# ============================================================

RUN set -eux; \
    python3 -m pip uninstall \
        -y \
        llama-cpp-python \
        2>/dev/null || true


# ============================================================
# 9. INSTALL PREBUILT LLAMA-CPP-PYTHON
#
# IMPORTANT:
#
# НЕ собираем llama-cpp-python из исходников.
#
# Берём готовый wheel из релизов JamePeng.
#
# Repository:
# https://github.com/JamePeng/llama-cpp-python
#
# Custom node itself recommends this source.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json
import platform
import sys
import urllib.request
import subprocess
import tempfile
import os
import re

PYTHON_VERSION = f"cp{sys.version_info.major}{sys.version_info.minor}"
ARCH = platform.machine().lower()

print("==========================================")
print("Searching JamePeng llama-cpp-python wheel")
print("==========================================")
print("Python ABI:", PYTHON_VERSION)
print("Architecture:", ARCH)

if ARCH not in ("x86_64", "amd64"):
    raise RuntimeError(
        f"Unsupported architecture: {ARCH}"
    )

API_URL = (
    "https://api.github.com/repos/"
    "JamePeng/llama-cpp-python/releases/latest"
)

request = urllib.request.Request(
    API_URL,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "Docker-build"
    }
)

print("Requesting latest release...")

with urllib.request.urlopen(
    request,
    timeout=60
) as response:
    release = json.load(response)

tag = release.get("tag_name", "unknown")

print("Latest release:", tag)

assets = release.get("assets", [])

wheels = []

for asset in assets:
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")

    if not name.endswith(".whl"):
        continue

    lower = name.lower()

    if PYTHON_VERSION.lower() not in lower:
        continue

    if "linux" not in lower:
        continue

    if not (
        "x86_64" in lower
        or "amd64" in lower
    ):
        continue

    wheels.append(
        {
            "name": name,
            "url": url
        }
    )

print("")
print("Compatible wheels found:")

for wheel in wheels:
    print(" -", wheel["name"])

if not wheels:
    raise RuntimeError(
        "No compatible JamePeng llama-cpp-python "
        f"wheel found for {PYTHON_VERSION} / Linux x86_64"
    )


# Prefer CUDA builds.
cuda_wheels = [
    wheel
    for wheel in wheels
    if any(
        x in wheel["name"].lower()
        for x in (
            "cuda",
            "cu12",
            "cu11",
            "cu118",
            "cu121",
            "cu122",
            "cu123",
            "cu124",
            "cu125",
            "cu126",
            "cu127",
            "cu128",
            "cu129"
        )
    )
]

if cuda_wheels:
    selected = cuda_wheels[0]
else:
    selected = wheels[0]

print("")
print("Selected wheel:")
print(selected["name"])
print("")
print("Installing prebuilt wheel...")

subprocess.check_call(
    [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--no-cache-dir",
        selected["url"]
    ]
)

print("")
print("JamePeng llama-cpp-python wheel installed")
PY


# ============================================================
# 10. VERIFY LLAMA-CPP
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import llama_cpp

print("==========================================")
print("llama_cpp successfully imported")
print("Version:")
print(getattr(
    llama_cpp,
    "__version__",
    "unknown"
))
print("==========================================")

if not hasattr(llama_cpp, "Llama"):
    raise RuntimeError(
        "llama_cpp.Llama is missing"
    )

from llama_cpp.llama_chat_format import (
    Llava15ChatHandler,
    Llava16ChatHandler,
    MoondreamChatHandler,
    NanoLlavaChatHandler,
    Llama3VisionAlphaChatHandler,
    MiniCPMv26ChatHandler,
)

print("Vision handlers: OK")

try:
    from llama_cpp.llama_chat_format import Qwen35ChatHandler
    print("Qwen35ChatHandler: AVAILABLE")
except ImportError:
    print(
        "WARNING: Qwen35ChatHandler is NOT available"
    )

print("")
print("llama_cpp verification PASSED")
PY


# ============================================================
# 11. PYTHON COMPILE CHECK
# ============================================================

RUN set -eux; \
    python3 -m py_compile \
        "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"; \
    echo "llama custom node Python syntax: OK"


# ============================================================
# 12. COMFYUI PYTHON CHECK
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}"; \
    python3 - <<'PY'
import sys

sys.path.insert(
    0,
    "/default-comfyui-bundle/ComfyUI"
)

import folder_paths

print("==========================================")
print("ComfyUI Python environment OK")
print("models_dir:", folder_paths.models_dir)
print("==========================================")
PY


# ============================================================
# 13. CREATE LLM MODEL DIRECTORY
#
# MODELS ARE NOT STORED IN DOCKER.
#
# RunPod Volume:
#
# /comfyui/models/LLM/
#
# Files:
#
# Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf
# Qwen3.5-9B-mmproj-F16.gguf
# ============================================================

RUN set -eux; \
    mkdir -p "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p "${COMFYUI_PATH}/user/default/workflows"; \
    test -d "${COMFYUI_PATH}/models/LLM"; \
    test -d "${COMFYUI_PATH}/user/default/workflows"; \
    echo "LLM directory ready"


# ============================================================
# 14. CLEAN OLD WORKFLOWS
# ============================================================

RUN set -eux; \
    for ROOT in \
        "${COMFYUI_PATH}" \
        "/ComfyUI" \
        "/workspace/ComfyUI" \
        "/opt/ComfyUI"; \
    do \
        if [ -d "${ROOT}" ]; then \
            find "${ROOT}" \
                -type d \
                -name "workflows" \
                -print0 | \
            while IFS= read -r -d '' WORKFLOW_DIR; do \
                echo "Cleaning workflow directory:"; \
                echo "${WORKFLOW_DIR}"; \
                find "${WORKFLOW_DIR}" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf {} +; \
            done; \
        fi; \
    done


# ============================================================
# 15. COPY CARUSEL WORKFLOW
# ============================================================

COPY CARUSEL.json /tmp/CARUSEL.json

RUN set -eux; \
    test -s /tmp/CARUSEL.json; \
    install \
        -m 0644 \
        /tmp/CARUSEL.json \
        "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json"; \
    rm -f /tmp/CARUSEL.json; \
    test -s \
        "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json"


# ============================================================
# 16. VALIDATE CARUSEL.JSON
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json
from pathlib import Path

workflow_path = Path(
    "/default-comfyui-bundle/ComfyUI/"
    "user/default/workflows/CARUSEL.json"
)

print("==========================================")
print("Validating CARUSEL.json")
print("==========================================")

if not workflow_path.exists():
    raise RuntimeError(
        f"Workflow not found: {workflow_path}"
    )

if workflow_path.stat().st_size == 0:
    raise RuntimeError(
        "CARUSEL.json is empty"
    )

with workflow_path.open(
    "r",
    encoding="utf-8"
) as f:
    workflow = json.load(f)

nodes = workflow.get("nodes", [])

if not nodes:
    raise RuntimeError(
        "CARUSEL.json contains no nodes"
    )

node_types = {
    node.get("type")
    for node in nodes
    if node.get("type")
}

print("Total nodes:", len(nodes))
print("Unique node types:", len(node_types))


required_llama_nodes = {
    "llama_cpp_parameters",
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
}

missing = (
    required_llama_nodes - node_types
)

if missing:
    raise RuntimeError(
        "Missing llama nodes: "
        + ", ".join(sorted(missing))
    )

print("")
print("Required llama nodes:")

for node_type in sorted(
    required_llama_nodes
):
    print("  OK:", node_type)


seedvr_nodes = {
    "SeedVR2LoadDiTModel",
    "SeedVR2LoadVAEModel",
    "SeedVR2VideoUpscaler",
}

found_seedvr = (
    seedvr_nodes & node_types
)

if found_seedvr:
    print("")
    print("SeedVR2 nodes:")

    for node_type in sorted(found_seedvr):
        print("  -", node_type)


known_custom_nodes = {
    "JDCN_StringToList",
    "ShowText|pysssss",
    "ProcessString",
    "CR Text Replace",
    "CR Text",
    "LayerUtility: ImageScaleByAspectRatio V2",
    "ttN int",
    "Label (rgthree)",
}

found_custom = (
    known_custom_nodes & node_types
)

print("")
print("Known custom nodes:")

for node_type in sorted(found_custom):
    print("  -", node_type)


print("")
print("Llama model references:")

for node in nodes:
    if node.get("type") in required_llama_nodes:
        print(
            node.get("type"),
            "=>",
            node.get("widgets_values", [])
        )

print("")
print("CARUSEL.json validation PASSED")
PY


# ============================================================
# 17. FINAL LLAMA NODE IMPORT
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}"; \
    python3 - <<'PY'
import sys

sys.path.insert(
    0,
    "/default-comfyui-bundle/ComfyUI"
)

print("Testing llama custom node import...")

import custom_nodes.ComfyUI-llama-cpp_vlm
PY


# ============================================================
# 18. FINAL CHECKS
# ============================================================

RUN set -eux; \
    test -f \
        "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"; \
    test -d \
        "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -d \
        "${COMFYUI_PATH}/models/LLM"; \
    test -f \
        "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json"; \
    echo ""; \
    echo "=================================================="; \
    echo "CARUSEL DOCKER IMAGE READY"; \
    echo "=================================================="; \
    echo "ComfyUI:       ${COMFYUI_PATH}"; \
    echo "Llama node:    INSTALLED"; \
    echo "llama_cpp:     INSTALLED"; \
    echo "CUDA wheel:    PREBUILT"; \
    echo "CARUSEL:       INSTALLED"; \
    echo "LLM models:    EXTERNAL VOLUME"; \
    echo "=================================================="


# ============================================================
# 19. WORKDIR
# ============================================================

WORKDIR ${COMFYUI_PATH}

USER root
