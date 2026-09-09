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
# 3. Определяем Python ABI
#
# Поддерживаем готовые Linux wheels:
#
# cp310
# cp311
# cp312
# cp313
# cp314
#
# Никакого GitHub API.
# ============================================================

RUN set -eux; \
    PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"; \
    echo "Detected Python: ${PY_VER}"; \
    case "${PY_VER}" in \
        3.10) \
            echo "Python ABI: cp310"; \
            ;; \
        3.11) \
            echo "Python ABI: cp311"; \
            ;; \
        3.12) \
            echo "Python ABI: cp312"; \
            ;; \
        3.13) \
            echo "Python ABI: cp313"; \
            ;; \
        3.14) \
            echo "Python ABI: cp314"; \
            ;; \
        *) \
            echo "ERROR: Unsupported Python version: ${PY_VER}"; \
            exit 1; \
            ;; \
    esac


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
# 7. Выбираем правильный готовый Linux CUDA wheel
#
# JamePeng
# llama-cpp-python 0.3.49
# CUDA 13.1
# Linux x86_64
#
# Версии и SHA256 зафиксированы.
# ============================================================

RUN set -eux; \
    PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"; \
    case "${PY_VER}" in \
        3.10) \
            LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp310-cp310-linux_x86_64.whl"; \
            LLAMA_SHA256="061bde5029f8862b75508104dfb428550353460f70ed512e2f4dcebbfa170a9f"; \
            ;; \
        3.11) \
            LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp311-cp311-linux_x86_64.whl"; \
            LLAMA_SHA256="68a239c8288fb9cd26085b5496909900f52e93fdffa4586c97a5b20263448229"; \
            ;; \
        3.12) \
            LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp312-cp312-linux_x86_64.whl"; \
            LLAMA_SHA256="278d7c5bcc40a16e93803ae0cea781f5d064353fc0a591d87836cc2faafc57b6"; \
            ;; \
        3.13) \
            LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp313-cp313-linux_x86_64.whl"; \
            LLAMA_SHA256="be02c47a2a4d0f9baafe2ff5b94ec6592e488e73dbb39ab3ca60e56153a029f0"; \
            ;; \
        3.14) \
            LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp314-cp314-linux_x86_64.whl"; \
            LLAMA_SHA256="11c69977e7cd8255d3d952f2655300fd30ea172b366d46ce0de55bf533c16793"; \
            ;; \
        *) \
            echo "ERROR: Unsupported Python version: ${PY_VER}"; \
            exit 1; \
            ;; \
    esac; \
    LLAMA_URL="https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.49-cu131-linux-20260831/${LLAMA_WHEEL}"; \
    echo "=============================================="; \
    echo "Installing llama-cpp-python"; \
    echo "Python: ${PY_VER}"; \
    echo "Wheel: ${LLAMA_WHEEL}"; \
    echo "URL: ${LLAMA_URL}"; \
    echo "=============================================="; \
    cd /tmp; \
    python3 -c "import urllib.request; urllib.request.urlretrieve('${LLAMA_URL}', '/tmp/${LLAMA_WHEEL}')"; \
    test -f "/tmp/${LLAMA_WHEEL}"; \
    echo "Checking SHA256..."; \
    echo "${LLAMA_SHA256}  /tmp/${LLAMA_WHEEL}" | sha256sum -c -; \
    echo "Installing wheel..."; \
    python3 -m pip install \
        --no-cache-dir \
        --force-reinstall \
        "/tmp/${LLAMA_WHEEL}"; \
    rm -f "/tmp/${LLAMA_WHEEL}"


# ============================================================
# 8. Проверяем llama-cpp-python
#
# НЕ импортируем ComfyUI.
# НЕ импортируем nodes.py.
# ============================================================

RUN set -eux; \
    python3 -c "import llama_cpp; from llama_cpp import Llama; print('llama_cpp version:', getattr(llama_cpp, '__version__', 'unknown')); print('Llama import: OK'); from llama_cpp.llama_chat_format import Llava15ChatHandler, Llava16ChatHandler, MoondreamChatHandler, NanoLlavaChatHandler, Llama3VisionAlphaChatHandler, MiniCPMv26ChatHandler; print('Standard vision handlers: OK'); from llama_cpp.llama_chat_format import Qwen35ChatHandler; print('Qwen35ChatHandler: OK'); print('llama-cpp-python verification: PASSED')"


# ============================================================
# 9. Статическая проверка custom node
#
# НЕ импортируем nodes.py.
# Это важно: импорт ComfyUI во время GitHub Actions
# может попытаться обратиться к NVIDIA.
# ============================================================

RUN set -eux; \
    python3 -c "import ast; path='/default-comfyui-bundle/ComfyUI/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py'; source=open(path, 'r', encoding='utf-8').read(); ast.parse(source, filename=path); required=['llama_cpp_parameters','llama_cpp_model_loader','llama_cpp_instruct_adv']; print('Checking required node definitions...'); [print(f'  {name}: FOUND') for name in required if name in source] if all(name in source for name in required) else (_ for _ in ()).throw(RuntimeError('Required Llama node definition missing')); print('nodes.py syntax: OK')"


# ============================================================
# 10. Создаём необходимые директории
#
# GGUF-модели НЕ помещаем в Docker.
# Они должны находиться на RunPod Volume:
#
# models/LLM/
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
# ============================================================

RUN set -eux; \
    python3 -c "import json; path='/tmp/CARUSEL.json'; data=json.load(open(path, 'r', encoding='utf-8')); assert isinstance(data, dict), 'CARUSEL.json root must be a JSON object'; nodes=data.get('nodes', []); links=data.get('links', []); print('=============================================='); print('CARUSEL.json'); print('=============================================='); print('JSON syntax: OK'); print('Workflow ID:', data.get('id')); print('Workflow version:', data.get('version')); print('Nodes:', len(nodes)); print('Links:', len(links)); llama=sorted(set(n.get('type') for n in nodes if isinstance(n.get('type'), str) and n.get('type').startswith('llama_cpp_'))); print(''); print('Llama nodes in workflow:'); [print('  ', x) for x in llama]; print('==============================================' )"


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
    echo "llama-cpp-python: 0.3.49+cu131"; \
    echo "Platform: Linux x86_64"; \
    echo "Custom node: ComfyUI-llama-cpp_vlm"; \
    echo "Workflow: CARUSEL.json"; \
    echo "LLM models: RunPod Volume"; \
    echo "=============================================="

WORKDIR ${COMFYUI_PATH}
