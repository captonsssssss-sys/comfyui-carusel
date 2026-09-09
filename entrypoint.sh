#!/bin/bash
set -e

COMFYUI_PATH=/default-comfyui-bundle/ComfyUI
LLM_DIR="${COMFYUI_PATH}/models/LLM"

mkdir -p "$LLM_DIR"

download_if_missing() {
    local url="$1"
    local output="$2"
    local name="$3"

    if [ -f "$output" ] && [ -s "$output" ]; then
        echo "[OK] $name already exists"
    else
        echo "[DOWNLOAD] $name ..."
        wget -q --show-progress --tries=10 --retry-connrefused -O "$output" "$url"
        echo "[DONE] $name"
    fi
}

echo "=============================================="
echo " Checking / Downloading large models..."
echo "=============================================="

# Основная модель (9.5 GB)
download_if_missing \
    "https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" \
    "${LLM_DIR}/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" \
    "Qwen3.5-9B-Uncensored Q8_0"

# mmproj
download_if_missing \
    "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/46af257bdeb3425e13cf8b701602e9b5173d4641/mmproj-F16.gguf" \
    "${LLM_DIR}/Qwen3.5-9B-mmproj-F16.gguf" \
    "Qwen3.5 mmproj-F16"

echo "=============================================="
echo " All models ready. Starting ComfyUI..."
echo "=============================================="

# Запуск ComfyUI (подстрой под свой базовый образ, если нужно)
exec python3 main.py --listen 0.0.0.0 --port 8188
