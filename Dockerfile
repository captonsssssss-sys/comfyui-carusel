FROM farmerfarmit/bitcoin:v6

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI

WORKDIR ${COMFYUI_PATH}

# ============================================================
# Базовая настройка
# ============================================================
RUN python3 -m pip install --upgrade pip setuptools wheel

# ============================================================
# llama-cpp-python
# ============================================================
RUN PY_MM=$(python3 -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')") && \
    case "$PY_MM" in \
        310) WHEEL="llama_cpp_python-0.3.49+cu131-cp310-cp310-linux_x86_64.whl" ;; \
        311) WHEEL="llama_cpp_python-0.3.49+cu131-cp311-cp311-linux_x86_64.whl" ;; \
        312) WHEEL="llama_cpp_python-0.3.49+cu131-cp312-cp312-linux_x86_64.whl" ;; \
        313) WHEEL="llama_cpp_python-0.3.49+cu131-cp313-cp313-linux_x86_64.whl" ;; \
        314) WHEEL="llama_cpp_python-0.3.49+cu131-cp314-cp314-linux_x86_64.whl" ;; \
        *) echo "Unsupported Python: $PY_MM" && exit 1 ;; \
    esac && \
    wget -q --show-progress -O /tmp/${WHEEL} \
        "https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.49-cu131-linux-20260831/${WHEEL}" && \
    python3 -m pip uninstall -y llama-cpp-python || true && \
    python3 -m pip install --no-cache-dir --force-reinstall /tmp/${WHEEL} && \
    rm -f /tmp/${WHEEL}

# ============================================================
# Custom Node
# ============================================================
WORKDIR ${COMFYUI_PATH}/custom_nodes

RUN rm -rf ComfyUI-llama-cpp_vlm && \
    git clone --depth 1 https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm.git && \
    if [ -f ComfyUI-llama-cpp_vlm/requirements.txt ]; then \
        python3 -m pip install -r ComfyUI-llama-cpp_vlm/requirements.txt; \
    fi

RUN python3 -m pip install numpy scipy pillow

# ============================================================
# Папки
# ============================================================
RUN mkdir -p \
    ${COMFYUI_PATH}/models/diffusion_models \
    ${COMFYUI_PATH}/models/loras \
    ${COMFYUI_PATH}/models/vae \
    ${COMFYUI_PATH}/models/text_encoders \
    ${COMFYUI_PATH}/models/LLM \
    ${COMFYUI_PATH}/user/default/workflows \
    ${COMFYUI_PATH}/input \
    ${COMFYUI_PATH}/output

# ============================================================
# Workflow
# ============================================================
RUN rm -rf ${COMFYUI_PATH}/user/default/workflows/*
COPY CARUSEL.json ${COMFYUI_PATH}/user/default/workflows/CARUSEL.json

# ============================================================
# Entrypoint
# ============================================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR ${COMFYUI_PATH}

EXPOSE 8188
EXPOSE 8888

ENTRYPOINT ["/entrypoint.sh"]
