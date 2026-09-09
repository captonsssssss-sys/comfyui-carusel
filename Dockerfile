# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI

# ============================================================
# SYSTEM
# ============================================================

RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            git \
            curl \
            ca-certificates \
            build-essential \
            cmake \
            pkg-config \
            python3-dev; \
        rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
            git \
            curl \
            ca-certificates \
            build-base \
            cmake \
            pkgconfig \
            python3-dev \
            bash; \
    elif command -v dnf >/dev/null 2>&1; then \
        dnf install -y \
            git \
            curl \
            ca-certificates \
            gcc \
            gcc-c++ \
            make \
            cmake \
            pkgconfig \
            python3-devel; \
        dnf clean all; \
    elif command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y \
            git \
            curl \
            ca-certificates \
            gcc \
            gcc-c++ \
            make \
            cmake \
            pkgconfig \
            python3-devel; \
        microdnf clean all; \
    else \
        echo "ERROR: package manager not found"; \
        exit 1; \
    fi; \
    git --version; \
    curl --version; \
    python3 --version; \
    cmake --version


# ============================================================
# CHECK COMFYUI
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -d "${COMFYUI_PATH}/models"; \
    test -d "${COMFYUI_PATH}/custom_nodes"; \
    echo "ComfyUI found at: ${COMFYUI_PATH}"


# ============================================================
# COMFYUI-LLAMA-CPP-VLM
# ============================================================

RUN set -eux; \
    rm -rf "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    git clone --depth 1 \
        https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm.git \
        "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -f "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"; \
    echo "ComfyUI-llama-cpp_vlm installed"


# ============================================================
# LLAMA NODE PYTHON REQUIREMENTS
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f "${NODE_PATH}/requirements.txt" ]; then \
        pip install --no-cache-dir \
            -r "${NODE_PATH}/requirements.txt"; \
    else \
        echo "No requirements.txt found in llama node"; \
    fi


# ============================================================
# GENERAL PYTHON DEPENDENCIES REQUIRED BY NODES.PY
# ============================================================

RUN pip install --no-cache-dir \
    numpy \
    scipy \
    pillow


# ============================================================
# LLAMA-CPP-PYTHON
#
# The node requires llama_cpp and specifically uses:
# - Llama
# - llama_chat_format
# - Qwen35ChatHandler
#
# Build with CUDA support.
# ============================================================

RUN set -eux; \
    python3 -m pip uninstall -y llama-cpp-python 2>/dev/null || true; \
    CMAKE_ARGS="-DGGML_CUDA=on" \
    FORCE_CMAKE=1 \
    python3 -m pip install \
        --no-cache-dir \
        --no-build-isolation \
        llama-cpp-python


# ============================================================
# VERIFY LLAMA-CPP
# ============================================================

RUN python3 - <<'PY'
import llama_cpp

print("llama_cpp imported successfully")
print("llama_cpp version:", getattr(llama_cpp, "__version__", "unknown"))

required = [
    "Llama",
]

for name in required:
    if not hasattr(llama_cpp, name):
        raise RuntimeError(
            f"llama_cpp is missing required object: {name}"
        )

from llama_cpp.llama_chat_format import (
    Llava15ChatHandler,
    Llava16ChatHandler,
    MoondreamChatHandler,
    NanoLlavaChatHandler,
    Llama3VisionAlphaChatHandler,
    MiniCPMv26ChatHandler,
)

print("llama_cpp chat handlers imported successfully")

try:
    from llama_cpp.llama_chat_format import Qwen35ChatHandler
    print("Qwen35ChatHandler: available")
except ImportError:
    print(
        "WARNING: Qwen35ChatHandler is not available "
        "in this llama-cpp-python build"
    )
PY


# ============================================================
# VERIFY LLAMA CUSTOM NODE
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
# VERIFY COMFYUI NODE IMPORT
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

print("ComfyUI Python environment OK")
print("models_dir:", folder_paths.models_dir)
PY


# ============================================================
# LLM MODEL DIRECTORY
#
# Models are intentionally NOT included in Docker.
# They must be placed on the RunPod Volume:
#
# /comfyui/models/LLM/
#
# ============================================================

RUN set -eux; \
    mkdir -p "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p "${COMFYUI_PATH}/user/default/workflows"


# ============================================================
# REGISTER LLM MODEL DIRECTORY
#
# ComfyUI-llama-cpp_vlm expects the LLM directory.
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}/models/LLM"


# ============================================================
# REMOVE OLD WORKFLOWS
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
                echo "Cleaning workflow directory: ${WORKFLOW_DIR}"; \
                find "${WORKFLOW_DIR}" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf {} +; \
            done; \
        fi; \
    done


# ============================================================
# COPY CARUSEL WORKFLOW
# ============================================================

COPY CARUSEL.json /tmp/CARUSEL.json

RUN set -eux; \
    test -s /tmp/CARUSEL.json; \
    install -m 0644 \
        /tmp/CARUSEL.json \
        "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json"; \
    rm -f /tmp/CARUSEL.json


# ============================================================
# VALIDATE CARUSEL.JSON
# ============================================================

RUN python3 - <<'PY'
import json
from pathlib import Path

workflow_path = Path(
    "/default-comfyui-bundle/ComfyUI/"
    "user/default/workflows/CARUSEL.json"
)

if not workflow_path.exists():
    raise RuntimeError(
        f"Workflow not found: {workflow_path}"
    )

with workflow_path.open("r", encoding="utf-8") as f:
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

print(f"Workflow nodes: {len(nodes)}")
print(f"Unique node types: {len(node_types)}")

# ------------------------------------------------------------
# Llama nodes
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

# ------------------------------------------------------------
# SeedVR2
# ------------------------------------------------------------

if "SeedVR2LoadDiTModel" in node_types:
    print("SeedVR2 nodes detected")

if "SeedVR2LoadVAEModel" in node_types:
    print("SeedVR2 VAE node detected")

if "SeedVR2VideoUpscaler" in node_types:
    print("SeedVR2 upscaler node detected")

# ------------------------------------------------------------
# Other known custom nodes
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

print("Known custom nodes detected:")

for node_type in sorted(found_custom):
    print("  -", node_type)

# ------------------------------------------------------------
# Print llama model references
# ------------------------------------------------------------

print("")
print("LLM/model references found in workflow:")

for node in nodes:
    node_type = node.get("type")

    if node_type in required_llama_nodes:
        print(
            f"  {node_type}: "
            f"{node.get('widgets_values', [])}"
        )

print("")
print("CARUSEL workflow validation passed")
PY


# ============================================================
# CHECK REQUIRED LLAMA MODEL DIRECTORY
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}/models/LLM"; \
    echo "LLM directory ready: ${COMFYUI_PATH}/models/LLM"


# ============================================================
# FINAL FILE CHECKS
# ============================================================

RUN set -eux; \
    test -f \
        "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json"; \
    test -f \
        "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"; \
    test -d \
        "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -d \
        "${COMFYUI_PATH}/models/LLM"; \
    echo "=================================================="; \
    echo "CARUSEL Docker image preparation complete"; \
    echo "ComfyUI: ${COMFYUI_PATH}"; \
    echo "Workflow: CARUSEL.json"; \
    echo "LLM models: external RunPod Volume"; \
    echo "=================================================="


WORKDIR ${COMFYUI_PATH}

USER root
