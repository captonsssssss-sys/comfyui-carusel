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

# llama-cpp-python

# Готовый CUDA wheel для Linux

# ============================================================

RUN python3 - <<'PY'
import sys
import urllib.request
import hashlib
import subprocess
import os

version = f"{sys.version_info.major}{sys.version_info.minor}"

wheels = {
"310": (
"llama_cpp_python-0.3.49+cu131-cp310-cp310-linux_x86_64.whl",
"061bde5029f8862b75508104dfb428550353460f70ed512e2f4dcebbfa170a9f",
),
"311": (
"llama_cpp_python-0.3.49+cu131-cp311-cp311-linux_x86_64.whl",
"68a239c8288fb9cd26085b5496909900f52e93fdffa4586c97a5b20263448229",
),
"312": (
"llama_cpp_python-0.3.49+cu131-cp312-cp312-linux_x86_64.whl",
"278d7c5bcc40a16e93803ae0cea781f5d064353fc0a591d87836cc2faafc57b6",
),
"313": (
"llama_cpp_python-0.3.49+cu131-cp313-cp313-linux_x86_64.whl",
"be02c47a2a4d0f9baafe2ff5b94ec6592e488e73dbb39ab3ca60e56153a029f0",
),
"314": (
"llama_cpp_python-0.3.49+cu131-cp314-cp314-linux_x86_64.whl",
"11c69977e7cd8255d3d952f2655300fd30ea172b366d46ce0de55bf533c16793",
),
}

if version not in wheels:
raise SystemExit(f"Unsupported Python version: {version}")

filename, expected_sha256 = wheels[version]

base_url = "https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.49-cu131-linux-20260831/"
url = base_url + filename
output = "/tmp/" + filename

print("Python version:", version)
print("Downloading:", url)

urllib.request.urlretrieve(url, output)

sha256 = hashlib.sha256()

with open(output, "rb") as f:
while True:
chunk = f.read(1024 * 1024)
if not chunk:
break
sha256.update(chunk)

actual_sha256 = sha256.hexdigest()

print("Expected SHA256:", expected_sha256)
print("Actual SHA256:  ", actual_sha256)

if actual_sha256 != expected_sha256:
raise SystemExit("SHA256 CHECK FAILED")

subprocess.check_call([
sys.executable,
"-m",
"pip",
"install",
"--no-cache-dir",
"--force-reinstall",
output,
])

os.remove(output)

print("llama-cpp-python installed successfully")
PY

# ============================================================

# Проверка llama-cpp-python

# ============================================================

RUN python3 -c "import llama_cpp; from llama_cpp import Llama; print('llama_cpp version:', getattr(llama_cpp, '**version**', 'unknown')); print('Llama import: OK')"

RUN python3 -c "from llama_cpp.llama_chat_format import Qwen35ChatHandler; print('Qwen35ChatHandler: OK')"

# ============================================================

# Custom Nodes

# ============================================================

WORKDIR ${COMFYUI_PATH}/custom_nodes

# Llama CPP VLM

RUN rm -rf ComfyUI-llama-cpp_vlm && 
git clone https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm.git

# ============================================================

# Requirements custom node

# ============================================================

RUN if [ -f "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/requirements.txt" ]; then 
python3 -m pip install -r "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/requirements.txt"; 
fi

# ============================================================

# Дополнительные библиотеки

# ============================================================

RUN python3 -m pip install 
numpy 
scipy 
pillow

# ============================================================

# Проверка nodes.py

# Только статическая проверка.

# ComfyUI здесь НЕ импортируем,

# потому что GitHub Actions не имеет NVIDIA GPU.

# ============================================================

RUN python3 -c "from pathlib import Path; import ast; p=Path('${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/nodes.py'); s=p.read_text(encoding='utf-8'); ast.parse(s); required=['llama_cpp_model_loader','llama_cpp_parameters','llama_cpp_instruct_adv']; missing=[x for x in required if x not in s]; assert not missing, 'Missing required nodes: ' + ', '.join(missing); print('ComfyUI-llama-cpp_vlm nodes.py: OK')"

# ============================================================

# Папки моделей

# ============================================================

RUN mkdir -p 
${COMFYUI_PATH}/models/diffusion_models 
${COMFYUI_PATH}/models/loras 
${COMFYUI_PATH}/models/vae 
${COMFYUI_PATH}/models/text_encoders 
${COMFYUI_PATH}/models/LLM 
${COMFYUI_PATH}/user/default/workflows 
${COMFYUI_PATH}/input 
${COMFYUI_PATH}/output

# ============================================================

# Универсальный загрузчик моделей

# ============================================================

RUN cat > /usr/local/bin/download-model <<'PY'
#!/usr/bin/env python3

import os
import sys
import time
import urllib.request

if len(sys.argv) != 3:
print("Usage: download-model URL OUTPUT")
sys.exit(1)

url = sys.argv[1]
output = sys.argv[2]

os.makedirs(os.path.dirname(output), exist_ok=True)

tmp = output + ".part"

for attempt in range(1, 6):
try:
print("=" * 70)
print("Download attempt:", attempt)
print("URL:", url)
print("Output:", output)
print("=" * 70)

```
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0"}
    )

    with urllib.request.urlopen(request, timeout=300) as response:
        total = response.headers.get("Content-Length")
        total = int(total) if total else None

        downloaded = 0
        last_print = 0

        with open(tmp, "wb") as f:
            while True:
                chunk = response.read(4 * 1024 * 1024)

                if not chunk:
                    break

                f.write(chunk)
                downloaded += len(chunk)

                now = time.time()

                if now - last_print >= 5:
                    if total:
                        percent = downloaded * 100 / total
                        print(
                            f"{downloaded / 1024 / 1024:.1f} MB / "
                            f"{total / 1024 / 1024:.1f} MB "
                            f"({percent:.1f}%)",
                            flush=True
                        )
                    else:
                        print(
                            f"{downloaded / 1024 / 1024:.1f} MB",
                            flush=True
                        )

                    last_print = now

    if not os.path.exists(tmp):
        raise RuntimeError("Temporary file does not exist")

    size = os.path.getsize(tmp)

    if size == 0:
        raise RuntimeError("Downloaded file is empty")

    os.replace(tmp, output)

    print(
        f"Downloaded successfully: "
        f"{size / 1024 / 1024:.1f} MB"
    )

    break

except Exception as e:
    print(f"Download failed: {e}")

    if os.path.exists(tmp):
        os.remove(tmp)

    if attempt == 5:
        raise

    time.sleep(5)
```

PY

RUN chmod +x /usr/local/bin/download-model

# ============================================================

# FireRed Image Edit

# ============================================================

RUN download-model 
"https://huggingface.co/cocorang/FireRed-Image-Edit-1.1-FP8_And_BF16/resolve/main/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" 
"${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors"

# ============================================================

# Qwen Image Lightning

# ============================================================

RUN download-model 
"https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors" 
"${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0 bf16.safetensors"

# ============================================================

# Qwen Image Edit F2P

# ============================================================

RUN download-model 
"https://huggingface.co/DiffSynth-Studio/Qwen-Image-Edit-F2P/resolve/main/edit_0928_lora_step40000.safetensors" 
"${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors"

# ============================================================

# Real Life LoRA

# ============================================================

RUN download-model 
"https://huggingface.co/IntelligenceLab/Loras/resolve/main/real_life_qwen.safetensors" 
"${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors"

# ============================================================

# Skin Fix

# ============================================================

RUN download-model 
"https://huggingface.co/labai-llc/skin-fix/resolve/7a4b0556b3b578f030f200d00f3a2cd404217b00/skin_realism-248951.safetensors" 
"${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors"

# ============================================================

# Qwen Image VAE

# ============================================================

RUN download-model 
"https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors" 
"${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors"

# ============================================================

# Qwen Text Encoder

# ============================================================

RUN download-model 
"https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b.safetensors" 
"${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors"

# ============================================================

# Qwen3.5 LLM

# ============================================================

RUN download-model 
"https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" 
"${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf"

# ============================================================

# Qwen3.5 mmproj

# ============================================================

RUN download-model 
"https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/46af257bdeb3425e13cf8b701602e9b5173d4641/mmproj-F16.gguf" 
"${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf"

# ============================================================

# Workflow

# ============================================================

RUN rm -rf ${COMFYUI_PATH}/user/default/workflows/*

COPY CARUSEL.json 
${COMFYUI_PATH}/user/default/workflows/CARUSEL.json

# ============================================================

# Проверка workflow

# ============================================================

RUN python3 -c "import json; from pathlib import Path; p=Path('${COMFYUI_PATH}/user/default/workflows/CARUSEL.json'); data=json.loads(p.read_text(encoding='utf-8')); assert isinstance(data,dict), 'CARUSEL.json root must be an object'; nodes=data.get('nodes',[]); print('CARUSEL.json: OK'); print('Workflow nodes:', len(nodes)); types={n.get('type') for n in nodes if isinstance(n,dict)}; required=['llama_cpp_model_loader','llama_cpp_parameters','llama_cpp_instruct_adv']; missing=[x for x in required if x not in types]; assert not missing, 'Missing workflow nodes: ' + ', '.join(missing); print('Required Llama nodes: OK')"

# ============================================================

# Проверка всех моделей

# ============================================================

RUN test -s "${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" && 
test -s "${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0 bf16.safetensors" && 
test -s "${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors" && 
test -s "${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors" && 
test -s "${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors" && 
test -s "${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors" && 
test -s "${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors" && 
test -s "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" && 
test -s "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf" && 
test -s "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json" && 
echo "============================================" && 
echo "ALL CARUSEL FILES ARE PRESENT" && 
echo "============================================"

# ============================================================

# Финальная информация

# ============================================================

RUN echo "============================================" && 
echo "CARUSEL DOCKER IMAGE READY" && 
echo "============================================" && 
echo "ComfyUI: ${COMFYUI_PATH}" && 
echo "Workflow: ${COMFYUI_PATH}/user/default/workflows/CARUSEL.json" && 
echo "Llama node: ${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm" && 
echo "============================================"
