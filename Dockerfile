FROM farmerfarmit/bitcoin:v6

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI

# ============================================================
# Базовая настройка
# ============================================================
WORKDIR ${COMFYUI_PATH}

RUN python3 -m pip install --upgrade pip setuptools wheel

# ============================================================
# llama-cpp-python (CUDA 13.1)
# ============================================================
RUN PY_MM=$(python3 -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')") && \
    case "$PY_MM" in \
        310) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp310-cp310-linux_x86_64.whl" ;; \
        311) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp311-cp311-linux_x86_64.whl" ;; \
        312) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp312-cp312-linux_x86_64.whl" ;; \
        313) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp313-cp313-linux_x86_64.whl" ;; \
        314) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp314-cp314-linux_x86_64.whl" ;; \
        *) echo "Unsupported Python version: $PY_MM"; exit 1 ;; \
    esac && \
    echo "$LLAMA_WHEEL" > /tmp/llama_wheel.txt && \
    wget -q --show-progress -O "/tmp/$LLAMA_WHEEL" \
        "https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.49-cu131-linux-20260831/$LLAMA_WHEEL" && \
    python3 -m pip uninstall -y llama-cpp-python || true && \
    python3 -m pip install --no-cache-dir --force-reinstall "/tmp/$LLAMA_WHEEL" && \
    rm -f /tmp/llama_cpp_python-*.whl /tmp/llama_wheel.txt

# ============================================================
# Проверка llama-cpp-python
# ============================================================
RUN python3 -c "import llama_cpp; from llama_cpp import Llama; print('llama_cpp version:', getattr(llama_cpp, '__version__', 'unknown')); print('Llama: OK')" && \
    python3 -c "from llama_cpp.llama_chat_format import Qwen35ChatHandler; print('Qwen35ChatHandler: OK')"

# ============================================================
# Custom Nodes
# ============================================================
WORKDIR ${COMFYUI_PATH}/custom_nodes

RUN rm -rf ComfyUI-llama-cpp_vlm && \
    git clone --depth 1 https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm.git

# ============================================================
# Requirements custom node
# ============================================================
RUN if [ -f "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/requirements.txt" ]; then \
        python3 -m pip install -r "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/requirements.txt"; \
    fi

# ============================================================
# Дополнительные библиотеки
# ============================================================
RUN python3 -m pip install numpy scipy pillow

# ============================================================
# Проверка nodes.py
# ============================================================
RUN python3 -c "\
from pathlib import Path; \
import ast; \
p = Path('${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py'); \
s = p.read_text(encoding='utf-8'); \
ast.parse(s); \
required = ['llama_cpp_model_loader', 'llama_cpp_parameters', 'llama_cpp_instruct_adv']; \
missing = [x for x in required if x not in s]; \
assert not missing, 'Missing required nodes: ' + ', '.join(missing); \
print('ComfyUI-llama-cpp_vlm: OK')"

# ============================================================
# Папки моделей
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
# FireRed Image Edit
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" \
    "https://huggingface.co/cocorang/FireRed-Image-Edit-1.1-FP8_And_BF16/resolve/main/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors"

# ============================================================
# Qwen Image Lightning
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors" \
    "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors"

# ============================================================
# Qwen Image Edit F2P
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors" \
    "https://huggingface.co/DiffSynth-Studio/Qwen-Image-Edit-F2P/resolve/main/edit_0928_lora_step40000.safetensors"

# ============================================================
# Real Life LoRA
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors" \
    "https://huggingface.co/IntelligenceLab/Loras/resolve/main/real_life_qwen.safetensors"

# ============================================================
# Skin Fix
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors" \
    "https://huggingface.co/labai-llc/skin-fix/resolve/7a4b0556b3b578f030f200d00f3a2cd404217b00/skin_realism-248951.safetensors"

# ============================================================
# Qwen Image VAE
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors" \
    "https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors"

# ============================================================
# Qwen Text Encoder
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors" \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b.safetensors"

# ============================================================
# Qwen3.5 LLM
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" \
    "https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf"

# ============================================================
# Qwen3.5 mmproj
# ============================================================
RUN wget -q --show-progress --tries=3 --retry-connrefused \
    -O "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf" \
    "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/46af257bdeb3425e13cf8b701602e9b5173d4641/mmproj-F16.gguf"

# ============================================================
# Workflow
# ============================================================
RUN rm -rf ${COMFYUI_PATH}/user/default/workflows/*
COPY CARUSEL.json ${COMFYUI_PATH}/user/default/workflows/CARUSEL.json

# ============================================================
# Проверка workflow
# ============================================================
RUN python3 -c "\
import json; \
from pathlib import Path; \
p = Path('${COMFYUI_PATH}/user/default/workflows/CARUSEL.json'); \
data = json.loads(p.read_text(encoding='utf-8')); \
assert isinstance(data, dict), 'CARUSEL.json root must be an object'; \
nodes = data.get('nodes', []); \
print('CARUSEL.json: OK'); \
print('Workflow nodes:', len(nodes)); \
types = {n.get('type') for n in nodes if isinstance(n, dict)}; \
required = ['llama_cpp_model_loader', 'llama_cpp_parameters', 'llama_cpp_instruct_adv']; \
missing = [x for x in required if x not in types]; \
assert not missing, 'Missing workflow nodes: ' + ', '.join(missing); \
print('Required Llama nodes: OK')"

# ============================================================
# Проверка моделей
# ============================================================
RUN test -s "${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" && \
    test -s "${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors" && \
    test -s "${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors" && \
    test -s "${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors" && \
    test -s "${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors" && \
    test -s "${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors" && \
    test -s "${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors" && \
    test -s "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" && \
    test -s "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf" && \
    test -s "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json" && \
    echo "============================================" && \
    echo "ALL REQUIRED FILES ARE PRESENT" && \
    echo "============================================"

# ============================================================
# Финал
# ============================================================
WORKDIR ${COMFYUI_PATH}

EXPOSE 8188
EXPOSE 8888
