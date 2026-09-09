FROM farmerfarmit/bitcoin:v6

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1
ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI

WORKDIR ${COMFYUI_PATH}

RUN python3 -m pip install --upgrade pip setuptools wheel

RUN set -eux; PY_MM="$(python3 -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')"; case "${PY_MM}" in 310) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp310-cp310-linux_x86_64.whl"; LLAMA_SHA256="061bde5029f8862b75508104dfb428550353460f70ed512e2f4dcebbfa170a9f" ;; 311) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp311-cp311-linux_x86_64.whl"; LLAMA_SHA256="68a239c8288fb9cd26085b5496909900f52e93fdffa4586c97a5b20263448229" ;; 312) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp312-cp312-linux_x86_64.whl"; LLAMA_SHA256="278d7c5bcc40a16e93803ae0cea781f5d064353fc0a591d87836cc2faafc57b6" ;; 313) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp313-cp313-linux_x86_64.whl"; LLAMA_SHA256="be02c47a2a4d0f9baafe2ff5b94ec6592e488e73dbb39ab3ca60e56153a029f0" ;; 314) LLAMA_WHEEL="llama_cpp_python-0.3.49+cu131-cp314-cp314-linux_x86_64.whl"; LLAMA_SHA256="11c69977e7cd8255d3d952f2655300fd30ea172b366d46ce0de55bf533c16793" ;; *) echo "Unsupported Python version: ${PY_MM}"; exit 1 ;; esac; echo "${LLAMA_WHEEL}" > /tmp/llama_wheel; echo "${LLAMA_SHA256}" > /tmp/llama_sha256

RUN rm -rf "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm" && git clone --depth 1 https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"

RUN if [ -f "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/requirements.txt" ]; then python3 -m pip install --no-cache-dir -r "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm/requirements.txt" || true; fi

RUN python3 -m pip install --no-cache-dir numpy scipy pillow

RUN set -eux; LLAMA_WHEEL="$(cat /tmp/llama_wheel)"; LLAMA_SHA256="$(cat /tmp/llama_sha256)"; LLAMA_URL="https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.49-cu131-linux-20260831/${LLAMA_WHEEL}"; echo "Downloading ${LLAMA_URL}"; python3 -c 'import urllib.request,sys; urllib.request.urlretrieve(sys.argv[1],sys.argv[2])' "${LLAMA_URL}" "/tmp/${LLAMA_WHEEL}"; echo "${LLAMA_SHA256}  /tmp/${LLAMA_WHEEL}" | sha256sum -c -; python3 -m pip uninstall -y llama-cpp-python 2>/dev/null || true; python3 -m pip install --no-cache-dir --force-reinstall "/tmp/${LLAMA_WHEEL}"; rm -f "/tmp/${LLAMA_WHEEL}"

RUN python3 -c 'import llama_cpp; from llama_cpp import Llama; from llama_cpp.llama_chat_format import Qwen35ChatHandler; print("llama_cpp version:", getattr(llama_cpp, "**version**", "unknown")); print("Qwen35ChatHandler: OK"); print("llama-cpp-python: OK")'

RUN python3 -c 'from pathlib import Path; import ast; root=Path("/default-comfyui-bundle/ComfyUI/custom_nodes/ComfyUI-llama-cpp_vlm"); nodes_py=root/"nodes.py"; source=nodes_py.read_text(encoding="utf-8"); ast.parse(source); required=["llama_cpp_model_loader","llama_cpp_parameters","llama_cpp_instruct_adv"]; missing=[x for x in required if x not in source]; assert not missing, "Required node source missing: "+", ".join(missing); print("Static nodes.py check: OK")'

RUN mkdir -p "${COMFYUI_PATH}/models/diffusion_models" "${COMFYUI_PATH}/models/loras" "${COMFYUI_PATH}/models/vae" "${COMFYUI_PATH}/models/text_encoders" "${COMFYUI_PATH}/models/LLM" "${COMFYUI_PATH}/user/default/workflows"

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

print("=" * 70)
print("Downloading:")
print(url)
print("To:")
print(output)
print("=" * 70)

for attempt in range(1, 6):
try:
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})

```
    with urllib.request.urlopen(req, timeout=120) as response:
        total = response.headers.get("Content-Length")
        total = int(total) if total else None
        downloaded = 0
        last_print = 0

        with open(tmp, "wb") as f:
            while True:
                chunk = response.read(1024 * 1024)

                if not chunk:
                    break

                f.write(chunk)
                downloaded += len(chunk)

                now = time.time()

                if now - last_print >= 5:
                    if total:
                        percent = downloaded * 100 / total
                        print(f"{downloaded / 1024 / 1024:.1f} MB / {total / 1024 / 1024:.1f} MB ({percent:.1f}%)", flush=True)
                    else:
                        print(f"{downloaded / 1024 / 1024:.1f} MB", flush=True)

                    last_print = now

    os.replace(tmp, output)

    size = os.path.getsize(output)

    if size == 0:
        raise RuntimeError("Downloaded file is empty")

    print(f"Downloaded successfully: {size / 1024 / 1024:.1f} MB")
    sys.exit(0)

except Exception as e:
    print(f"Download attempt {attempt}/5 failed: {e}")

    try:
        if os.path.exists(tmp):
            os.remove(tmp)
    except Exception:
        pass

    if attempt == 5:
        raise

    time.sleep(5)
```

PY

RUN chmod +x /usr/local/bin/download-model

RUN download-model "https://huggingface.co/cocorang/FireRed-Image-Edit-1.1-FP8_And_BF16/resolve/main/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" "${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors"

RUN download-model "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors" "${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0 bf16.safetensors"

RUN download-model "https://huggingface.co/DiffSynth-Studio/Qwen-Image-Edit-F2P/resolve/main/edit_0928_lora_step40000.safetensors" "${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors"

RUN download-model "https://huggingface.co/IntelligenceLab/Loras/resolve/main/real_life_qwen.safetensors" "${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors"

RUN download-model "https://huggingface.co/labai-llc/skin-fix/resolve/7a4b0556b3b578f030f200d00f3a2cd404217b00/skin_realism-248951.safetensors" "${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors"

RUN download-model "https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors" "${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors"

RUN download-model "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b.safetensors" "${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors"

RUN download-model "https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf"

RUN download-model "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/46af257bdeb3425e13cf8b701602e9b5173d4641/mmproj-F16.gguf" "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf"

COPY CARUSEL.json /tmp/CARUSEL.json

RUN python3 -c 'import json; from pathlib import Path; path=Path("/tmp/CARUSEL.json"); workflow=json.loads(path.read_text(encoding="utf-8")); assert isinstance(workflow,dict), "CARUSEL.json root is not an object"; nodes=workflow.get("nodes",[]); print("Workflow JSON: OK"); print("Workflow nodes:",len(nodes)); node_types={node.get("type") for node in nodes if isinstance(node,dict)}; required=["llama_cpp_model_loader","llama_cpp_parameters","llama_cpp_instruct_adv"]; missing=[x for x in required if x not in node_types]; assert not missing, "Required workflow nodes missing: "+", ".join(missing); print("Required Llama nodes: OK")'

RUN install -m 0644 /tmp/CARUSEL.json "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json" && rm -f /tmp/CARUSEL.json

RUN test -s "${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" && test -s "${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0 bf16.safetensors" && test -s "${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors" && test -s "${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors" && test -s "${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors" && test -s "${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors" && test -s "${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors" && test -s "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" && test -s "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf" && test -s "${COMFYUI_PATH}/user/default/workflows/CARUSEL.json" && echo "============================================" && echo "ALL REQUIRED FILES ARE PRESENT" && echo "============================================"

RUN echo "===== CARUSEL IMAGE READY =====" && echo "ComfyUI: ${COMFYUI_PATH}" && echo "Workflow: ${COMFYUI_PATH}/user/default/workflows/CARUSEL.json" && echo "Llama node: ${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm" && echo "===== MODELS =====" && find "${COMFYUI_PATH}/models" -maxdepth 2 -type f \(-name "*.safetensors" -o -name "*.gguf"\) -printf "  %p\n" | sort
