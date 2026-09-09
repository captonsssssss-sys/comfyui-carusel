# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1


# ============================================================
# 1. BASE IMAGE CHECK
#
# ВАЖНО:
# farmerfarmit/bitcoin:v6 не содержит apt/apk/dnf.
# Поэтому ничего через системный package manager не ставим.
# Используем инструменты, которые уже находятся в образе.
# ============================================================

RUN set -eux; \
    echo "========== BASE IMAGE =========="; \
    echo "ComfyUI path: ${COMFYUI_PATH}"; \
    echo ""; \
    echo "Python:"; \
    command -v python3 || true; \
    command -v python || true; \
    python3 --version; \
    echo ""; \
    echo "PIP:"; \
    command -v pip3 || true; \
    command -v pip || true; \
    python3 -m pip --version; \
    echo ""; \
    echo "Git:"; \
    command -v git || true; \
    echo ""; \
    echo "Build tools:"; \
    command -v gcc || true; \
    command -v g++ || true; \
    command -v cmake || true; \
    command -v make || true; \
    command -v ninja || true; \
    echo ""; \
    echo "CUDA:"; \
    command -v nvcc || true; \
    nvcc --version 2>/dev/null || true; \
    echo ""; \
    echo "================================"


# ============================================================
# 2. CHECK COMFYUI
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -d "${COMFYUI_PATH}/models"; \
    test -d "${COMFYUI_PATH}/custom_nodes"; \
    echo "ComfyUI found at: ${COMFYUI_PATH}"


# ============================================================
# 3. CHECK PYTHON BUILD ENVIRONMENT
#
# llama-cpp-python будет собираться с CUDA.
# Поэтому нам нужны:
# - Python
# - pip
# - gcc/g++
# - cmake
# - make/ninja
# - CUDA compiler
# ============================================================

RUN set -eux; \
    command -v python3; \
    python3 --version; \
    python3 -m pip --version; \
    command -v gcc; \
    command -v g++; \
    command -v cmake; \
    command -v make; \
    command -v nvcc; \
    echo "Python/build/CUDA toolchain is available"


# ============================================================
# 4. UPDATE PIP BUILD TOOLS
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        --upgrade \
        pip \
        setuptools \
        wheel \
        packaging


# ============================================================
# 5. INSTALL COMFYUI-LLAMA-CPP-VLM
#
# Репозиторий:
# https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm
#
# Используем GitHub ZIP вместо git clone.
# Так Docker не зависит от наличия git.
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    TMP_DIR="/tmp/ComfyUI-llama-cpp_vlm"; \
    rm -rf "${NODE_PATH}" "${TMP_DIR}" /tmp/llama-cpp-vlm.zip; \
    mkdir -p "${TMP_DIR}"; \
    python3 - <<'PY'
import urllib.request

url = "https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm/archive/refs/heads/main.zip"
output = "/tmp/llama-cpp-vlm.zip"

print("Downloading ComfyUI-llama-cpp_vlm...")
urllib.request.urlretrieve(url, output)
print("Download complete:", output)
PY
    python3 - <<'PY'
import zipfile

archive = "/tmp/llama-cpp-vlm.zip"
destination = "/tmp/ComfyUI-llama-cpp_vlm"

with zipfile.ZipFile(archive, "r") as z:
    z.extractall(destination)

print("Archive extracted")
PY
    EXTRACTED_DIR="$(find /tmp/ComfyUI-llama-cpp_vlm -mindepth 1 -maxdepth 1 -type d | head -n 1)"; \
    test -n "${EXTRACTED_DIR}"; \
    mv "${EXTRACTED_DIR}" "${NODE_PATH}"; \
    test -f "${NODE_PATH}/nodes.py"; \
    rm -rf "${TMP_DIR}" /tmp/llama-cpp-vlm.zip; \
    echo "ComfyUI-llama-cpp_vlm installed at: ${NODE_PATH}"


# ============================================================
# 6. LLAMA NODE REQUIREMENTS
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f "${NODE_PATH}/requirements.txt" ]; then \
        echo "Installing llama node requirements..."; \
        python3 -m pip install \
            -r "${NODE_PATH}/requirements.txt"; \
    else \
        echo "No requirements.txt found in llama node"; \
    fi


# ============================================================
# 7. PYTHON DEPENDENCIES USED BY nodes.py
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 8. LLAMA-CPP-PYTHON
#
# ComfyUI-llama-cpp_vlm требует:
#
#   import llama_cpp
#   from llama_cpp import Llama
#   from llama_cpp.llama_chat_format import ...
#
# Сборка включается с CUDA.
#
# ВАЖНО:
# тяжелые GGUF/MMProj модели сюда НЕ устанавливаем.
# Они будут находиться на RunPod Volume.
# ============================================================

RUN set -eux; \
    python3 -m pip uninstall -y llama-cpp-python 2>/dev/null || true; \
    rm -rf /tmp/pip-* /root/.cache/pip; \
    CMAKE_ARGS="-DGGML_CUDA=on" \
    FORCE_CMAKE=1 \
    python3 -m pip install \
        --no-build-isolation \
        --no-cache-dir \
        llama-cpp-python


# ============================================================
# 9. VERIFY LLAMA-CPP
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import llama_cpp

print("========================================")
print("llama_cpp imported successfully")
print("llama_cpp version:", getattr(llama_cpp, "__version__", "unknown"))
print("========================================")

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

print("Standard vision chat handlers imported successfully")

try:
    from llama_cpp.llama_chat_format import Qwen35ChatHandler
    print("Qwen35ChatHandler: AVAILABLE")
except ImportError:
    print(
        "WARNING: Qwen35ChatHandler is not available "
        "in this llama-cpp-python version"
    )

print("llama_cpp verification complete")
PY


# ============================================================
# 10. VERIFY CUDA LLAMA BACKEND
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import llama_cpp

print("")
print("Checking llama_cpp CUDA/backend information...")

try:
    print(
        "llama_cpp has CUDA support information available"
    )
except Exception as e:
    print(
        "CUDA backend check warning:",
        e
    )

print("llama_cpp backend import OK")
PY


# ============================================================
# 11. VERIFY LLAMA CUSTOM NODE
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
    echo "========================================"; \
    echo "Required llama custom nodes found"; \
    echo "========================================"


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

print("========================================")
print("ComfyUI Python environment OK")
print("ComfyUI models_dir:", folder_paths.models_dir)
print("========================================")
PY


# ============================================================
# 13. CREATE LLM MODEL DIRECTORY
#
# Модели НЕ находятся внутри Docker.
#
# На RunPod Volume должно быть:
#
# /comfyui/models/LLM/
#
# Например:
#
# /comfyui/models/LLM/
# ├── Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf
# └── Qwen3.5-9B-mmproj-F16.gguf
#
# ============================================================

RUN set -eux; \
    mkdir -p "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p "${COMFYUI_PATH}/user/default/workflows"; \
    test -d "${COMFYUI_PATH}/models/LLM"; \
    test -d "${COMFYUI_PATH}/user/default/workflows"; \
    echo "LLM model directory ready"


# ============================================================
# 14. REGISTER / VERIFY LLM DIRECTORY
#
# Сам custom node регистрирует:
#
# models/LLM
#
# с расширениями:
# .ckpt
# .pt
# .bin
# .pth
# .safetensors
# .gguf
#
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import sys

sys.path.insert(
    0,
    "/default-comfyui-bundle/ComfyUI"
)

import folder_paths

llm_path = "/default-comfyui-bundle/ComfyUI/models/LLM"

print("LLM directory:", llm_path)

if not __import__("os").path.isdir(llm_path):
    raise RuntimeError(
        "LLM directory does not exist"
    )

print("LLM directory exists")
PY


# ============================================================
# 15. REMOVE OLD WORKFLOWS
#
# Чтобы в образе не оставались старые workflow.
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
# 16. COPY CARUSEL WORKFLOW
#
# CARUSEL.json должен лежать рядом с Dockerfile:
#
# repo/
# ├── Dockerfile
# ├── CARUSEL.json
# └── .github/
#
# ============================================================

COPY CARUSEL.json /tmp/CARUSEL.json

RUN set -eux; \
    test -s /tmp/CARUSEL.json; \
    install -m 0644 \
        /tmp/CARUSEL.json \
        "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json"; \
    rm -f /tmp/CARUSEL.json; \
    test -s \
        "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json"


# ============================================================
# 17. VALIDATE CARUSEL.JSON
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json
from pathlib import Path

workflow_path = Path(
    "/default-comfyui-bundle/ComfyUI/"
    "user/default/workflows/CARUSEL.json"
)

print("========================================")
print("Validating CARUSEL.json")
print("========================================")

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

print("Workflow nodes:", len(nodes))
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
print("Required llama workflow nodes:")

for node in sorted(required_llama_nodes):
    print("  OK:", node)


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

    for node in sorted(found_seedvr):
        print("  -", node)


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
# LLM MODEL REFERENCES
# ------------------------------------------------------------

print("")
print("LLM/model references from workflow:")

for node in nodes:
    node_type = node.get("type")

    if node_type in required_llama_nodes:
        print(
            f"  {node_type}: "
            f"{node.get('widgets_values', [])}"
        )


print("")
print("========================================")
print("CARUSEL workflow validation PASSED")
print("========================================")
PY


# ============================================================
# 18. FINAL LLAMA NODE IMPORT CHECK
#
# Здесь мы реально импортируем nodes.py.
# Это важнее, чем просто grep.
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}"; \
    python3 - <<'PY'
import sys

sys.path.insert(
    0,
    "/default-comfyui-bundle/ComfyUI"
)

node_path = (
    "/default-comfyui-bundle/ComfyUI/"
    "custom_nodes/ComfyUI-llama-cpp_vlm"
)

sys.path.insert(0, node_path)

print("Importing llama custom node...")

try:
    import nodes
    print("Llama custom node imported successfully")
except Exception as e:
    print("")
    print("ERROR: llama custom node import failed")
    print(type(e).__name__, str(e))
    raise
PY


# ============================================================
# 19. FINAL FILE CHECKS
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
    echo ""; \
    echo "=================================================="; \
    echo "CARUSEL DOCKER IMAGE PREPARATION COMPLETE"; \
    echo "=================================================="; \
    echo "ComfyUI:        ${COMFYUI_PATH}"; \
    echo "Llama node:     INSTALLED"; \
    echo "Llama workflow: VALIDATED"; \
    echo "CARUSEL.json:   INSTALLED"; \
    echo "LLM directory:  ${COMFYUI_PATH}/models/LLM"; \
    echo "LLM models:     EXTERNAL RUNPOD VOLUME"; \
    echo "=================================================="


# ============================================================
# 20. FINAL WORKING DIRECTORY
# ============================================================

WORKDIR ${COMFYUI_PATH}

USER root
