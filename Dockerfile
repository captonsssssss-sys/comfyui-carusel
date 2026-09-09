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
# llama-cpp-python (CUDA 13.1)
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
# Проверка llama-cpp
# ============================================================
RUN python3 -c "import llama_cpp; from llama_cpp import Llama; print('llama_cpp:', getattr(llama_cpp, '__version__', 'ok'))" && \
    python3 -c "from llama_cpp.llama_chat_format import Qwen35ChatHandler; print('Qwen35ChatHandler: OK')"

# ============================================================
# Custom Node
# ============================================================
WORKDIR ${COMFYUI_PATH}/custom_nodes

RUN rm -rf ComfyUI-llama-cpp_vlm && \
    git clone --depth 1 https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm.git && \
    if [ -f ComfyUI-llama-cpp_vlm/requirements.txt ]; then \
        python3 -m pip install -r ComfyUI-llama-cpp_vlm/requirements.txt; \
    fi

# ============================================================
# Дополнительные пакеты
# ============================================================
RUN python3 -m pip install numpy scipy pillow

# ============================================================
# Создание папок
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
# Модели
# ============================================================

# FireRed
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors \
    "https://huggingface.co/cocorang/FireRed-Image-Edit-1.1-FP8_And_BF16/resolve/main/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors"

# Lightning
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors \
    "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors"

# F2P LoRA
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors \
    "https://huggingface.co/DiffSynth-Studio/Qwen-Image-Edit-F2P/resolve/main/edit_0928_lora_step40000.safetensors"

# Real Life
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors \
    "https://huggingface.co/IntelligenceLab/Loras/resolve/main/real_life_qwen.safetensors"

# Skin Fix
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors \
    "https://huggingface.co/labai-llc/skin-fix/resolve/7a4b0556b3b578f030f200d00f3a2cd404217b00/skin_realism-248951.safetensors"

# VAE
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors \
    "https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors"

# Text Encoder
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b.safetensors"

# LLM
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf \
    "https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf"

# mmproj
RUN wget -q --show-progress --tries=5 --retry-connrefused \
    -O ${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf \
    "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/46af257bdeb3425e13cf8b701602e9b5173d4641/mmproj-F16.gguf"

# ============================================================
# Workflow
# ============================================================
RUN rm -rf ${COMFYUI_PATH}/user/default/workflows/*
COPY CARUSEL.json ${COMFYUI_PATH}/user/default/workflows/CARUSEL.json

# ============================================================
# Финальные проверки
# ============================================================
RUN python3 -c "\
from pathlib import Path; import json, ast; \
p = Path('${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py'); \
ast.parse(p.read_text(encoding='utf-8')); \
print('nodes.py: OK')" && \
\
python3 -c "\
import json; from pathlib import Path; \
data = json.loads(Path('${COMFYUI_PATH}/user/default/workflows/CARUSEL.json').read_text(encoding='utf-8')); \
print('CARUSEL.json: OK, nodes:', len(data.get('nodes', [])))" && \
\
test -s ${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors && \
test -s ${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors && \
test -s ${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors && \
test -s ${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors && \
test -s ${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors && \
test -s ${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors && \
test -s ${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors && \
test -s ${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf && \
test -s ${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf && \
echo "========================================" && \
echo "ALL FILES OK - BUILD SUCCESSFUL" && \
echo "========================================"

# ============================================================
# Финал
# ============================================================
WORKDIR ${COMFYUI_PATH}

EXPOSE 8188
EXPOSE 8888
