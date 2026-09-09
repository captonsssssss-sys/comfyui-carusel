# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1


# ============================================================
# 1. BASE IMAGE
# ============================================================

RUN set -eux; \
    echo "=========================================="; \
    echo "BASE IMAGE CHECK"; \
    echo "=========================================="; \
    python3 --version; \
    python3 -m pip --version; \
    echo "Python executable:"; \
    command -v python3; \
    echo "Architecture:"; \
    uname -m; \
    echo "=========================================="


# ============================================================
# 2. CHECK COMFYUI
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -d "${COMFYUI_PATH}/models"; \
    test -d "${COMFYUI_PATH}/custom_nodes"; \
    echo "ComfyUI found: ${COMFYUI_PATH}"


# ============================================================
# 3. PYTHON PACKAGING
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        --upgrade \
        pip \
        setuptools \
        wheel \
        packaging


# ============================================================
# 4. DOWNLOAD LLAMA CUSTOM NODE
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import os
import shutil
import urllib.request
import zipfile

COMFYUI = "/default-comfyui-bundle/ComfyUI"

NODE_PATH = os.path.join(
    COMFYUI,
    "custom_nodes",
    "ComfyUI-llama-cpp_vlm"
)

ZIP_PATH = "/tmp/llama-cpp-vlm.zip"
EXTRACT_PATH = "/tmp/llama-cpp-vlm"

URL = (
    "https://github.com/"
    "lihaoyun6/ComfyUI-llama-cpp_vlm/"
    "archive/refs/heads/main.zip"
)

print("Downloading ComfyUI-llama-cpp_vlm...")

urllib.request.urlretrieve(
    URL,
    ZIP_PATH
)

print("Download complete")

if os.path.exists(EXTRACT_PATH):
    shutil.rmtree(EXTRACT_PATH)

if os.path.exists(NODE_PATH):
    shutil.rmtree(NODE_PATH)

os.makedirs(
    EXTRACT_PATH,
    exist_ok=True
)

with zipfile.ZipFile(
    ZIP_PATH,
    "r"
) as archive:
    archive.extractall(EXTRACT_PATH)

directories = [
    os.path.join(EXTRACT_PATH, name)
    for name in os.listdir(EXTRACT_PATH)
    if os.path.isdir(
        os.path.join(EXTRACT_PATH, name)
    )
]

if not directories:
    raise RuntimeError(
        "Could not extract llama node repository"
    )

shutil.move(
    directories[0],
    NODE_PATH
)

os.remove(ZIP_PATH)
shutil.rmtree(
    EXTRACT_PATH,
    ignore_errors=True
)

if not os.path.isfile(
    os.path.join(NODE_PATH, "nodes.py")
):
    raise RuntimeError(
        "nodes.py was not found"
    )

print(
    "Installed:",
    NODE_PATH
)
PY


# ============================================================
# 5. VERIFY CUSTOM NODE
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
    echo "All required llama nodes found"


# ============================================================
# 6. LLAMA NODE REQUIREMENTS
# ============================================================

RUN set -eux; \
    NODE_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f "${NODE_PATH}/requirements.txt" ]; then \
        python3 -m pip install \
            -r "${NODE_PATH}/requirements.txt"; \
    else \
        echo "No llama requirements.txt"; \
    fi


# ============================================================
# 7. PYTHON DEPENDENCIES
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 8. REMOVE EXISTING LLAMA-CPP
# ============================================================

RUN set -eux; \
    python3 -m pip uninstall \
        -y \
        llama-cpp-python \
        2>/dev/null || true


# ============================================================
# 9. INSTALL LLAMA-CPP-PYTHON
#
# IMPORTANT:
#
# НЕ СБИРАЕМ C++.
#
# Используем официальный PyPI package.
#
# Если подходящего wheel нет, pip может попытаться
# собрать source package.
#
# Поэтому сначала проверяем Python ABI.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import sys
import platform

print("==========================================")
print("LLAMA-CPP ENVIRONMENT")
print("==========================================")
print("Python:", sys.version)
print(
    "Python ABI:",
    f"cp{sys.version_info.major}{sys.version_info.minor}"
)
print(
    "Architecture:",
    platform.machine()
)
print("==========================================")
PY


# ============================================================
# 10. INSTALL LLAMA-CPP-PYTHON
#
# JamePeng release index.
#
# The custom node specifically recommends using
# JamePeng's llama-cpp-python builds.
# ============================================================

RUN set -eux; \
    PY_VER="$(python3 -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"; \
    PY_FULL="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"; \
    echo "Python ABI: ${PY_VER}"; \
    echo "Python version: ${PY_FULL}"; \
    echo ""; \
    echo "Installing llama-cpp-python..."; \
    python3 -m pip install \
        --no-cache-dir \
        --extra-index-url \
        "https://github.com/JamePeng/llama-cpp-python/releases/expanded_assets/latest" \
        llama-cpp-python


# ============================================================
# 11. VERIFY LLAMA-CPP IMPORT
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import llama_cpp

print("==========================================")
print("LLAMA-CPP VERIFICATION")
print("==========================================")

print(
    "Version:",
    getattr(
        llama_cpp,
        "__version__",
        "unknown"
    )
)

if not hasattr(
    llama_cpp,
    "Llama"
):
    raise RuntimeError(
        "llama_cpp.Llama is missing"
    )

print("Llama class: OK")

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
    print(
        "Qwen35ChatHandler: AVAILABLE"
    )
except ImportError:
    print(
        "WARNING:"
        " Qwen35ChatHandler unavailable"
    )

print("==========================================")
print("LLAMA-CPP VERIFICATION PASSED")
print("==========================================")
PY


# ============================================================
# 12. CHECK CUSTOM NODE PYTHON
# ============================================================

RUN set -eux; \
    python3 -m py_compile \
        "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"; \
    echo "Llama custom node syntax: OK"


# ============================================================
# 13. CHECK COMFYUI PYTHON
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
print("COMFYUI PYTHON CHECK")
print("==========================================")
print(
    "models_dir:",
    folder_paths.models_dir
)
print("ComfyUI Python: OK")
print("==========================================")
PY


# ============================================================
# 14. CREATE LLM DIRECTORY
# ============================================================

RUN set -eux; \
    mkdir -p \
        "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p \
        "${COMFYUI_PATH}/user/default/workflows"; \
    test -d \
        "${COMFYUI_PATH}/models/LLM"; \
    test -d \
        "${COMFYUI_PATH}/user/default/workflows"; \
    echo "LLM directory ready"


# ============================================================
# 15. CLEAN OLD WORKFLOWS
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
            while IFS= read -r -d '' DIR; do \
                echo "Cleaning workflow directory: ${DIR}"; \
                find "${DIR}" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf {} +; \
            done; \
        fi; \
    done


# ============================================================
# 16. COPY CARUSEL
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
# 17. VALIDATE CARUSEL
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json
from pathlib import Path

path = Path(
    "/default-comfyui-bundle/ComfyUI/"
    "user/default/workflows/CARUSEL.json"
)

if not path.exists():
    raise RuntimeError(
        "CARUSEL.json not found"
    )

with path.open(
    "r",
    encoding="utf-8"
) as f:
    workflow = json.load(f)

nodes = workflow.get(
    "nodes",
    []
)

if not nodes:
    raise RuntimeError(
        "CARUSEL.json contains no nodes"
    )

node_types = {
    node.get("type")
    for node in nodes
    if node.get("type")
}

required = {
    "llama_cpp_parameters",
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
}

missing = required - node_types

if missing:
    raise RuntimeError(
        "Missing llama workflow nodes: "
        + ", ".join(
            sorted(missing)
        )
    )

print("==========================================")
print("CARUSEL VALIDATION")
print("==========================================")
print(
    "Total nodes:",
    len(nodes)
)
print(
    "Unique node types:",
    len(node_types)
)

for node_type in sorted(required):
    print(
        "Llama node OK:",
        node_type
    )

print("")
print("CARUSEL.json validation PASSED")
print("==========================================")
PY


# ============================================================
# 18. FINAL LLAMA NODE IMPORT
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}"; \
    python3 - <<'PY'
import importlib.util

node_file = (
    "/default-comfyui-bundle/ComfyUI/"
    "custom_nodes/ComfyUI-llama-cpp_vlm/"
    "nodes.py"
)

print(
    "Testing:",
    node_file
)

spec = importlib.util.spec_from_file_location(
    "comfyui_llama_cpp_vlm",
    node_file
)

if spec is None or spec.loader is None:
    raise RuntimeError(
        "Could not load llama nodes.py"
    )

module = importlib.util.module_from_spec(
    spec
)

spec.loader.exec_module(module)

print(
    "ComfyUI-llama-cpp_vlm import: OK"
)
PY


# ============================================================
# 19. FINAL CHECK
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
    echo "CARUSEL IMAGE BUILD PREPARATION COMPLETE"; \
    echo "=================================================="; \
    echo "ComfyUI:       ${COMFYUI_PATH}"; \
    echo "Llama node:    INSTALLED"; \
    echo "llama_cpp:     INSTALLED"; \
    echo "CARUSEL:       INSTALLED"; \
    echo "LLM models:    EXTERNAL VOLUME"; \
    echo "=================================================="


# ============================================================
# 20. WORKDIR
# ============================================================

WORKDIR ${COMFYUI_PATH}

USER root
