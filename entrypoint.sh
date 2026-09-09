#!/bin/bash
set -e

COMFYUI_PATH="/default-comfyui-bundle/ComfyUI"

download_if_missing() {
    local url="$1"
    local output="$2"
    local name="$3"

    if [ -f "$output" ] && [ -s "$output" ]; then
        echo "[OK] $name уже есть"
    else
        echo "[DOWNLOAD] Скачиваю $name ..."
        mkdir -p "$(dirname "$output")"
        wget --show-progress --tries=15 --retry-connrefused -O "$output" "$url"
        echo "[DONE] $name скачан"
    fi
}

echo "=================================================="
echo " Начинаю проверку и скачивание моделей..."
echo "=================================================="

# ========== Diffusion Model ==========
download_if_missing \
    "https://huggingface.co/cocorang/FireRed-Image-Edit-1.1-FP8_And_BF16/resolve/main/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" \
    "${COMFYUI_PATH}/models/diffusion_models/FireRed-Image-Edit-1.1_fp8mixed_comfy.safetensors" \
    "FireRed-Image-Edit-1.1"

# ========== LoRAs ==========
download_if_missing \
    "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors" \
    "${COMFYUI_PATH}/models/loras/Qwen-Image-Lightning-8steps-V2.0-bf16.safetensors" \
    "Qwen-Image-Lightning"

download_if_missing \
    "https://huggingface.co/DiffSynth-Studio/Qwen-Image-Edit-F2P/resolve/main/edit_0928_lora_step40000.safetensors" \
    "${COMFYUI_PATH}/models/loras/Qwen-Image-Edit-F2P.safetensors" \
    "Qwen-Image-Edit-F2P"

download_if_missing \
    "https://huggingface.co/IntelligenceLab/Loras/resolve/main/real_life_qwen.safetensors" \
    "${COMFYUI_PATH}/models/loras/real_life_qwen.safetensors" \
    "real_life_qwen"

download_if_missing \
    "https://huggingface.co/labai-llc/skin-fix/resolve/7a4b0556b3b578f030f200d00f3a2cd404217b00/skin_realism-248951.safetensors" \
    "${COMFYUI_PATH}/models/loras/Skin_Fix_rank64.safetensors" \
    "Skin_Fix"

# ========== VAE ==========
download_if_missing \
    "https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors" \
    "${COMFYUI_PATH}/models/vae/qwen_image_vae.safetensors" \
    "qwen_image_vae"

# ========== Text Encoder ==========
download_if_missing \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b.safetensors" \
    "${COMFYUI_PATH}/models/text_encoders/qwen_2.5_vl_7b.safetensors" \
    "qwen_2.5_vl_7b"

# ========== LLM ==========
download_if_missing \
    "https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" \
    "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" \
    "Qwen3.5-9B-Uncensored Q8_0"

download_if_missing \
    "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/46af257bdeb3425e13cf8b701602e9b5173d4641/mmproj-F16.gguf" \
    "${COMFYUI_PATH}/models/LLM/Qwen3.5-9B-mmproj-F16.gguf" \
    "Qwen3.5 mmproj"

echo "=================================================="
echo " Все модели готовы. Запускаю ComfyUI..."
echo "=================================================="

# Запуск ComfyUI
exec python3 main.py --listen 0.0.0.0 --port 8188
