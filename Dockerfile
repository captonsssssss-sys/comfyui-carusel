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
    python3 --version; \
    python3 -m pip --version


# ============================================================
# 2. Базовые Python-инструменты
# ============================================================

RUN set -eux; \
    python3 -m pip install --upgrade \
        pip \
        setuptools \
        wheel \
        packaging


# ============================================================
# 3. Устанавливаем только нужный custom node:
#    ComfyUI-llama-cpp_vlm
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
# 4. Python-зависимости custom node
#
# ВАЖНО:
# requirements.txt устанавливаем отдельно.
# llama-cpp-python здесь специально НЕ собираем из исходников.
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f requirements.txt ]; then \
        python3 -m pip install -r requirements.txt; \
    fi


# ============================================================
# 5. Базовые зависимости, которые использует nodes.py
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 6. Устанавливаем готовый llama-cpp-python wheel
#
# Не собираем llama-cpp-python через CMake.
# Ищем совместимый wheel в релизах JamePeng.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json
import os
import platform
import subprocess
import sys
import tempfile
import urllib.request
from packaging.tags import sys_tags
from packaging.utils import parse_wheel_filename

API_URL = "https://api.github.com/repos/JamePeng/llama-cpp-python/releases/latest"

print("Python:", sys.version)
print("Platform:", platform.platform())
print("Architecture:", platform.machine())
print("Downloading release information...")

request = urllib.request.Request(
    API_URL,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "docker-build-llama-cpp"
    }
)

with urllib.request.urlopen(request, timeout=60) as response:
    release = json.load(response)

tag = release.get("tag_name", "unknown")
assets = release.get("assets", [])

print("Latest JamePeng release:", tag)
print("Assets:", len(assets))

supported_tags = set(sys_tags())

candidates = []

for asset in assets:
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")

    if not name.endswith(".whl"):
        continue

    try:
        distribution, version, build, wheel_tags = parse_wheel_filename(name)
    except Exception:
        continue

    if not supported_tags.intersection(wheel_tags):
        continue

    lower_name = name.lower()

    # Prefer CUDA wheels when available.
    cuda_score = 0
    if "cuda" in lower_name:
        cuda_score += 100
    if "cu12" in lower_name:
        cuda_score += 20
    if "cu11" in lower_name:
        cuda_score += 10

    # Prefer x86_64 wheels on the RunPod AMD64 platform.
    arch_score = 0
    if "x86_64" in lower_name or "amd64" in lower_name:
        arch_score += 20

    # Prefer manylinux wheels.
    platform_score = 0
    if "manylinux" in lower_name:
        platform_score += 10

    score = cuda_score + arch_score + platform_score

    candidates.append(
        (
            score,
            name,
            url,
            str(version),
        )
    )

if not candidates:
    print("")
    print("ERROR: No compatible llama-cpp-python wheel was found.")
    print("")
    print("Available wheel assets:")
    for asset in assets:
        name = asset.get("name", "")
        if name.endswith(".whl"):
            print(" -", name)
    raise SystemExit(1)

candidates.sort(reverse=True)

print("")
print("Compatible wheel candidates:")
for score, name, url, version in candidates:
    print(f"  score={score:3d}  version={version}  {name}")

score, wheel_name, wheel_url, wheel_version = candidates[0]

print("")
print("Selected wheel:")
print(wheel_name)
print(wheel_url)
print("")

with tempfile.TemporaryDirectory() as tmp:
    wheel_path = os.path.join(tmp, wheel_name)

    print("Downloading selected wheel...")
    urllib.request.urlretrieve(wheel_url, wheel_path)

    print("Installing selected wheel...")
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

print("")
print("llama-cpp-python installation completed.")
PY


# ============================================================
# 7. Проверяем llama-cpp-python
#
# НЕ импортируем ComfyUI.
# НЕ импортируем nodes.py.
# НЕ трогаем CUDA.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import llama_cpp
from llama_cpp import Llama

print("llama_cpp imported successfully")
print("llama_cpp version:", getattr(llama_cpp, "__version__", "unknown"))
print("Llama:", Llama)

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
except ImportError as e:
    print("WARNING: Qwen35ChatHandler is not available:")
    print(e)
    print("")
    print("The installed llama-cpp-python package may not contain")
    print("the Qwen3.5 handler required by the selected custom node.")
    raise
PY


# ============================================================
# 8. Статически проверяем nodes.py
#
# ВАЖНО:
# Никакого import nodes.py здесь нет.
# Поэтому GitHub Actions не пытается обращаться к NVIDIA GPU.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import ast
import os

path = "/default-comfyui-bundle/ComfyUI/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"

with open(path, "r", encoding="utf-8") as f:
    source = f.read()

ast.parse(source, filename=path)

required_names = [
    "llama_cpp_parameters",
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
]

for name in required_names:
    if name not in source:
        raise RuntimeError(f"Expected node name not found in nodes.py: {name}")

print("nodes.py syntax: OK")
print("Required Llama node definitions detected:")
for name in required_names:
    print(" -", name)
PY


# ============================================================
# 9. Создаём директорию LLM
#
# Сами GGUF-модели сюда НЕ копируем.
# RunPod Volume будет монтироваться отдельно.
# ============================================================

RUN set -eux; \
    mkdir -p "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p "${COMFYUI_PATH}/workflows"


# ============================================================
# 10. Копируем workflow
# ============================================================

COPY CARUSEL.json /tmp/CARUSEL.json


# ============================================================
# 11. Проверяем только JSON-синтаксис
#
# НИКАКИХ проверок class_type.
# НИКАКИХ требований к количеству nodes.
# НИКАКОЙ попытки запускать workflow.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json

path = "/tmp/CARUSEL.json"

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict):
    raise RuntimeError("CARUSEL.json root must be a JSON object")

print("CARUSEL.json: valid JSON")
print("Workflow ID:", data.get("id"))
print("Workflow version:", data.get("version"))
print("Node count:", len(data.get("nodes", [])))
print("Link count:", len(data.get("links", [])))

# Просто информативно показываем Llama nodes,
# но НЕ падаем из-за формата workflow.

llama_nodes = []

for node in data.get("nodes", []):
    node_type = node.get("type")

    if isinstance(node_type, str) and node_type.startswith("llama_cpp_"):
        llama_nodes.append(node_type)

print("Llama nodes found in workflow:")
for node_type in sorted(set(llama_nodes)):
    print(" -", node_type)
PY


# ============================================================
# 12. Кладём workflow в ComfyUI
# ============================================================

RUN set -eux; \
    cp /tmp/CARUSEL.json "${COMFYUI_PATH}/workflows/CARUSEL.json"; \
    rm -f /tmp/CARUSEL.json; \
    test -f "${COMFYUI_PATH}/workflows/CARUSEL.json"


# ============================================================
# 13. Финальная проверка файлов
#
# Никаких CUDA вызовов.
# Никакого запуска ComfyUI.
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -d "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -f "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py"; \
    test -d "${COMFYUI_PATH}/models/LLM"; \
    test -f "${COMFYUI_PATH}/workflows/CARUSEL.json"; \
    python3 -c "import llama_cpp; print('FINAL llama_cpp check: OK')"; \
    echo ""; \
    echo "=============================================="; \
    echo " Docker image preparation completed"; \
    echo "=============================================="; \
    echo "ComfyUI: ${COMFYUI_PATH}"; \
    echo "Llama node: installed"; \
    echo "Workflow: installed"; \
    echo "LLM models: expected on RunPod Volume"; \
    echo "=============================================="


WORKDIR ${COMFYUI_PATH}
