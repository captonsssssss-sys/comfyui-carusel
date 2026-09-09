# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1


# ============================================================
# 1. BASE IMAGE CHECK
# ============================================================

RUN set -eux; \
    echo "=========================================="; \
    echo "Checking base image"; \
    echo "=========================================="; \
    echo "ComfyUI: ${COMFYUI_PATH}"; \
    echo ""; \
    echo "Python:"; \
    command -v python3; \
    python3 --version; \
    echo ""; \
    echo "Pip:"; \
    python3 -m pip --version; \
    echo ""; \
    echo "Build tools:"; \
    command -v gcc; \
    command -v g++; \
    command -v cmake; \
    command -v make; \
    echo ""; \
    echo "CUDA:"; \
    command -v nvcc; \
    nvcc --version; \
    echo ""; \
    echo "Base image check passed"


# ============================================================
# 2. CHECK COMFYUI
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -d "${COMFYUI_PATH}/models"; \
    test -d "${COMFYUI_PATH}/custom_nodes"; \
    echo "ComfyUI found at: ${COMFYUI_PATH}"


# ============================================================
# 3. UPDATE PYTHON BUILD TOOLS
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        --upgrade \
        pip \
        setuptools \
        wheel \
        packaging


# ============================================================
# 4. DOWNLOAD COMFYUI-LLAMA-CPP-VLM
#
# Source:
# https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm
#
# Не используем apt/apk/dnf.
# Не используем git.
# Репозиторий скачивается напрямую через Python.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import os
import shutil
import urllib.request
import zipfile

comfy_path = "/default-comfyui-bundle/ComfyUI"
node_path = os.path.join(
    comfy_path,
    "custom_nodes",
    "ComfyUI-llama-cpp_vlm",
)

tmp_zip = "/tmp/llama-cpp-vlm.zip"
tmp_dir = "/tmp/llama-cpp-vlm"

url = (
    "https://github.com/"
    "lihaoyun6/ComfyUI-llama-cpp_vlm/"
    "archive/refs/heads/main.zip"
)

print("Downloading ComfyUI-llama-cpp_vlm...")
urllib.request.urlretrieve(url, tmp_zip)

print("Download complete")

if os.path.exists(tmp_dir):
    shutil.rmtree(tmp_dir)

if os.path.exists(node_path):
    shutil.rmtree(node_path)

os.makedirs(tmp_dir, exist_ok=True)

print("Extracting archive...")

with zipfile.ZipFile(tmp_zip, "r") as archive:
    archive.extractall(tmp_dir)

extracted_dirs = [
    os.path.join(tmp_dir, name)
    for name in os.listdir(tmp_dir)
    if os.path.isdir(os.path.join(tmp_dir, name))
]

if not extracted_dirs:
    raise RuntimeError(
        "Could not find extracted llama node directory"
    )

source_dir = extracted_dirs[0]

shutil.move(source_dir, node_path)

os.remove(tmp_zip)
shutil.rmtree(tmp_dir, ignore_errors=True)

nodes_file = os.path.join(node_path, "nodes.py")

if not os.path.isfile(nodes_file):
    raise RuntimeError(
        f"nodes.py not found: {nodes_file}"
    )

print("ComfyUI-llama-cpp_vlm installed:")
print(node_path)
PY


# ============================================================
# 5. VERIFY DOWNLOADED LLAMA NODE
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -d "${NODE_PATH}"; \
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
        echo "Installing llama node requirements..."; \
        python3 -m pip install \
            -r "${NODE_PATH}/requirements.txt"; \
    else \
        echo "No requirements.txt found"; \
    fi


# ============================================================
# 7. PYTHON DEPENDENCIES REQUIRED BY nodes.py
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 8. REMOVE EXISTING LLAMA-CPP-PYTHON
# ============================================================

RUN set -eux; \
    python3 -m pip uninstall \
        -y \
        llama-cpp-python \
        2>/dev/null || true


# ============================================================
# 9. BUILD LLAMA-CPP-PYTHON WITH CUDA
#
# The node requires:
#
#   import llama_cpp
#   from llama_cpp import Llama
#
# CUDA backend:
#
#   GGML_CUDA=on
#
# Models are NOT included in Docker.
# ============================================================

RUN set -eux; \
    echo "=========================================="; \
    echo "Building llama-cpp-python with CUDA"; \
    echo "=========================================="; \
    CMAKE_ARGS="-DGGML_CUDA=on" \
    FORCE_CMAKE=1 \
    python3 -m pip install \
        --no-build-isolation \
        --no-cache-dir \
        llama-cpp-python


# ============================================================
# 10. VERIFY LLAMA-CPP
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import llama_cpp

print("==========================================")
print("llama_cpp import successful")
print("Version:", getattr(
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

print("Vision chat handlers: OK")

try:
    from llama_cpp.llama_chat_format import Qwen35ChatHandler
    print("Qwen35ChatHandler: AVAILABLE")
except ImportError:
    print(
        "WARNING: Qwen35ChatHandler is not available "
        "in this llama-cpp-python build"
    )

print("llama_cpp verification passed")
PY


# ============================================================
# 11. CHECK LLAMA CUSTOM NODE PYTHON SYNTAX
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    python3 -m py_compile \
        "${NODE_PATH}/nodes.py"; \
    echo "llama custom node Python syntax: OK"


# ============================================================
# 12. VERIFY COMFYUI PYTHON ENVIRONMENT
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
print("ComfyUI Python environment: OK")
print("models_dir:", folder_paths.models_dir)
print("==========================================")
PY


# ============================================================
# 13. CREATE LLM DIRECTORY
#
# Heavy models are NOT stored in Docker.
#
# RunPod Volume:
#
# /comfyui/models/LLM/
#
# Expected models:
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
                echo "Cleaning: ${WORKFLOW_DIR}"; \
                find "${WORKFLOW_DIR}" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf {} +; \
            done; \
        fi; \
    done


# ============================================================
# 15. COPY CARUSEL WORKFLOW
#
# Repository structure:
#
# comfyui-carusel/
# ├── Dockerfile
# ├── CARUSEL.json
# └── .github/
#     └── workflows/
#         └── docker.yml
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


# ------------------------------------------------------------
# LLAMA NODES
# ------------------------------------------------------------

required_llama_nodes = {
    "llama_cpp_parameters",
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
}

missing_llama = (
    required_llama_nodes - node_types
)

if missing_llama:
    raise RuntimeError(
        "Missing llama nodes in workflow: "
        + ", ".join(sorted(missing_llama))
    )

print("")
print("Required llama nodes:")

for node_type in sorted(required_llama_nodes):
    print("  OK:", node_type)


# ------------------------------------------------------------
# SEEDVR2
# ------------------------------------------------------------

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
    print("SeedVR2 nodes detected:")

    for node_type in sorted(found_seedvr):
        print("  -", node_type)


# ------------------------------------------------------------
# OTHER KNOWN CUSTOM NODES
# ------------------------------------------------------------

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
print("Known custom nodes detected:")

for node_type in sorted(found_custom):
    print("  -", node_type)


# ------------------------------------------------------------
# MODEL REFERENCES
# ------------------------------------------------------------

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
# 17. FINAL FILE CHECK
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
    echo "ComfyUI:        ${COMFYUI_PATH}"; \
    echo "Llama node:     INSTALLED"; \
    echo "llama_cpp:      INSTALLED"; \
    echo "CUDA build:     ENABLED"; \
    echo "CARUSEL.json:   INSTALLED"; \
    echo "LLM models:     EXTERNAL VOLUME"; \
    echo "=================================================="


# ============================================================
# 18. FINAL WORKING DIRECTORY
# ============================================================

WORKDIR ${COMFYUI_PATH}

USER root
