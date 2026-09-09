# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

# ============================================================
# 1. Проверяем базовый образ
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -f "${COMFYUI_PATH}/main.py"; \
    echo "=== Python ==="; \
    python3 --version; \
    echo "=== pip ==="; \
    python3 -m pip --version


# ============================================================
# 2. Базовые Python-инструменты
# ============================================================

RUN set -eux; \
    python3 -m pip install --upgrade \
        pip \
        setuptools \
        wheel


# ============================================================
# 3. Проверяем Python ABI
#
# Нам нужен CPython 3.12, потому что ниже устанавливается:
#
# llama_cpp_python-0.3.49+cu131-cp312-cp312-linux_x86_64.whl
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import sys

print("Python:", sys.version)

if sys.version_info[:2] != (3, 12):
    raise RuntimeError(
        "This Dockerfile expects Python 3.12, "
        f"but the base image has Python {sys.version_info.major}.{sys.version_info.minor}. "
        "Use the matching cp311/cp313 wheel if the base image uses another Python version."
    )

print("Python 3.12 ABI: OK")
PY


# ============================================================
# 4. Устанавливаем custom node
#
# ComfyUI-llama-cpp_vlm
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
# 5. Зависимости custom node
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f requirements.txt ]; then \
        python3 -m pip install -r requirements.txt; \
    fi


# ============================================================
# 6. Зависимости, используемые nodes.py
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 7. Устанавливаем КОНКРЕТНЫЙ Linux CUDA wheel
#
# JamePeng
# llama-cpp-python 0.3.49
# CUDA 13.1
# CPython 3.12
# Linux x86_64
#
# Больше никакого GitHub API / latest.
# ============================================================

ENV LLAMA_CPP_VERSION=0.3.49
ENV LLAMA_CPP_WHEEL=llama_cpp_python-0.3.49+cu131-cp312-cp312-linux_x86_64.whl
ENV LLAMA_CPP_URL=https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.49-cu131-linux-20260831/llama_cpp_python-0.3.49%2Bcu131-cp312-cp312-linux_x86_64.whl
ENV LLAMA_CPP_SHA256=278d7c5bcc40a16e93803ae0cea781f5d064353fc0a591d87836cc2faafc57b6

RUN set -eux; \
    cd /tmp; \
    echo "Downloading ${LLAMA_CPP_WHEEL}"; \
    python3 - <<'PY'
import os
import urllib.request

url = os.environ["LLAMA_CPP_URL"]
filename = os.environ["LLAMA_CPP_WHEEL"]
output = os.path.join("/tmp", filename)

print("URL:", url)
print("Output:", output)

request = urllib.request.Request(
    url,
    headers={
        "User-Agent": "Docker-llama-cpp-installer"
    }
)

with urllib.request.urlopen(request, timeout=120) as response:
    with open(output, "wb") as f:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)

size = os.path.getsize(output)

print("Downloaded:", size, "bytes")

if size < 1000000:
    raise RuntimeError(
        f"Downloaded wheel is suspiciously small: {size} bytes"
    )
PY
    echo "Checking SHA256..."; \
    echo "${LLAMA_CPP_SHA256}  /tmp/${LLAMA_CPP_WHEEL}" | sha256sum -c -; \
    echo "Installing llama-cpp-python..."; \
    python3 -m pip install \
        --no-cache-dir \
        --force-reinstall \
        "/tmp/${LLAMA_CPP_WHEEL}"; \
    rm -f "/tmp/${LLAMA_CPP_WHEEL}"


# ============================================================
# 8. Проверяем llama-cpp-python
#
# Здесь НЕ импортируем ComfyUI.
# Здесь НЕ импортируем nodes.py.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import llama_cpp
from llama_cpp import Llama

print("==============================================")
print(" llama-cpp-python")
print("==============================================")
print("Version:", getattr(llama_cpp, "__version__", "unknown"))
print("Llama:", Llama)
print("Import: OK")

from llama_cpp.llama_chat_format import (
    Llava15ChatHandler,
    Llava16ChatHandler,
    MoondreamChatHandler,
    NanoLlavaChatHandler,
    Llama3VisionAlphaChatHandler,
    MiniCPMv26ChatHandler,
)

print("Standard vision handlers: OK")

try:
    from llama_cpp.llama_chat_format import Qwen35ChatHandler
    print("Qwen35ChatHandler: OK")
except ImportError as e:
    print("Qwen35ChatHandler: FAILED")
    print(e)
    raise

print("==============================================")
print(" llama-cpp-python verification: PASSED")
print("==============================================")
PY


# ============================================================
# 9. Статическая проверка custom node
#
# НЕ импортируем nodes.py.
# Это важно: импорт ComfyUI во время GitHub Actions
# может попытаться обратиться к NVIDIA.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import ast

path = "/default-comfyui-bundle/ComfyUI/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"

with open(path, "r", encoding="utf-8") as f:
    source = f.read()

ast.parse(source, filename=path)

required_names = [
    "llama_cpp_parameters",
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
]

print("Checking required node definitions...")

for name in required_names:
    if name not in source:
        raise RuntimeError(
            f"Expected node name not found in nodes.py: {name}"
        )
    print(f"  {name}: FOUND")

print("nodes.py syntax: OK")
PY


# ============================================================
# 10. Создаём необходимые директории
#
# GGUF-модели НЕ помещаем в Docker.
# Они должны находиться на RunPod Volume:
#
# /.../models/LLM/
# ============================================================

RUN set -eux; \
    mkdir -p "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p "${COMFYUI_PATH}/workflows"


# ============================================================
# 11. Копируем workflow
# ============================================================

COPY CARUSEL.json /tmp/CARUSEL.json


# ============================================================
# 12. Проверяем JSON workflow
#
# Только синтаксис JSON.
# Никаких попыток запускать workflow.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json

path = "/tmp/CARUSEL.json"

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict):
    raise RuntimeError("CARUSEL.json root must be a JSON object")

nodes = data.get("nodes", [])
links = data.get("links", [])

print("==============================================")
print(" CARUSEL.json")
print("==============================================")
print("JSON syntax: OK")
print("Workflow ID:", data.get("id"))
print("Workflow version:", data.get("version"))
print("Nodes:", len(nodes))
print("Links:", len(links))

llama_nodes = []

for node in nodes:
    node_type = node.get("type")

    if isinstance(node_type, str) and node_type.startswith("llama_cpp_"):
        llama_nodes.append(node_type)

print("")
print("Llama nodes in workflow:")

for node_type in sorted(set(llama_nodes)):
    print("  ", node_type)

print("==============================================")
PY


# ============================================================
# 13. Устанавливаем workflow в ComfyUI
# ============================================================

RUN set -eux; \
    cp /tmp/CARUSEL.json "${COMFYUI_PATH}/workflows/CARUSEL.json"; \
    rm -f /tmp/CARUSEL.json; \
    test -f "${COMFYUI_PATH}/workflows/CARUSEL.json"


# ============================================================
# 14. Финальная проверка
#
# Никакого запуска ComfyUI.
# Никакого обращения к CUDA.
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -f "${COMFYUI_PATH}/main.py"; \
    test -d "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -f "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"; \
    test -d "${COMFYUI_PATH}/models/LLM"; \
    test -f "${COMFYUI_PATH}/workflows/CARUSEL.json"; \
    python3 -c "import llama_cpp; print('FINAL llama_cpp import: OK')"; \
    echo ""; \
    echo "=============================================="; \
    echo " BUILD PREPARATION COMPLETE"; \
    echo "=============================================="; \
    echo "Base: farmerfarmit/bitcoin:v6"; \
    echo "Python: 3.12"; \
    echo "llama-cpp-python: 0.3.49+cu131"; \
    echo "Platform: Linux x86_64"; \
    echo "Custom node: ComfyUI-llama-cpp_vlm"; \
    echo "Workflow: CARUSEL.json"; \
    echo "LLM models: RunPod Volume"; \
    echo "=============================================="

WORKDIR ${COMFYUI_PATH}
