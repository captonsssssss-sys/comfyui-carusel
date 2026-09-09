# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1


# ============================================================
# 1. CHECK BASE IMAGE
# ============================================================

RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -f "${COMFYUI_PATH}/main.py"; \
    python3 --version; \
    python3 -m pip --version


# ============================================================
# 2. UPDATE PYTHON BUILD TOOLS
# ============================================================

RUN set -eux; \
    python3 -m pip install --upgrade \
        pip \
        setuptools \
        wheel \
        packaging


# ============================================================
# 3. INSTALL COMFYUI-LLAMA-CPP-VLM
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}/custom_nodes"; \
    rm -rf ComfyUI-llama-cpp_vlm; \
    git clone --depth 1 \
        https://github.com/lihaoyun6/ComfyUI-llama-cpp_vlm.git \
        ComfyUI-llama-cpp_vlm; \
    test -f ComfyUI-llama-cpp_vlm/nodes.py; \
    test -f ComfyUI-llama-cpp_vlm/__init__.py; \
    test -d ComfyUI-llama-cpp_vlm/support


# ============================================================
# 4. INSTALL CUSTOM NODE REQUIREMENTS
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    if [ -f requirements.txt ]; then \
        python3 -m pip install -r requirements.txt; \
    fi


# ============================================================
# 5. BASIC PYTHON DEPENDENCIES
# ============================================================

RUN set -eux; \
    python3 -m pip install \
        numpy \
        scipy \
        pillow


# ============================================================
# 6. INSTALL LLAMA-CPP-PYTHON
#
# Use prebuilt JamePeng wheel.
# We DO NOT compile llama-cpp-python from source.
#
# The script:
#   - detects Python version
#   - detects compatible wheel tags
#   - searches JamePeng releases
#   - selects compatible wheel
#   - prefers CUDA build
#   - downloads it
#   - installs it
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json
import os
import platform
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

from packaging.tags import sys_tags
from packaging.utils import parse_wheel_filename


API_URL = (
    "https://api.github.com/repos/"
    "JamePeng/llama-cpp-python/releases"
    "?per_page=100"
)

print("=" * 80)
print("SEARCHING JAMEPENG LLAMA-CPP-PYTHON WHEELS")
print("=" * 80)

print("Python:", sys.version)
print("Machine:", platform.machine())
print("Platform:", platform.platform())

compatible_tags = set(sys_tags())

print("Compatible wheel tags:")
for tag in list(compatible_tags)[:30]:
    print("  ", tag)

print("=" * 80)
print("Requesting GitHub releases...")
print("=" * 80)

request = urllib.request.Request(
    API_URL,
    headers={
        "User-Agent": "ComfyUI-Docker-Build",
        "Accept": "application/vnd.github+json",
    },
)

try:
    with urllib.request.urlopen(
        request,
        timeout=60,
    ) as response:
        raw = response.read()
        print("GitHub API status:", response.status)

except urllib.error.HTTPError as exc:
    print("GitHub API HTTP ERROR:", exc.code)

    try:
        body = exc.read().decode(
            "utf-8",
            errors="replace",
        )
        print(body)
    except Exception:
        pass

    raise

except Exception as exc:
    print("GitHub API ERROR:", repr(exc))
    raise


releases = json.loads(raw)

if not isinstance(releases, list):
    raise RuntimeError(
        "Unexpected GitHub releases API response"
    )


# ============================================================
# FIND COMPATIBLE WHEELS
# ============================================================

candidates = []

for release_index, release in enumerate(releases):

    release_name = (
        release.get("name")
        or release.get("tag_name")
        or "unknown"
    )

    for asset in release.get("assets", []):

        asset_name = asset.get("name", "")
        asset_url = asset.get("browser_download_url")

        if not asset_name.endswith(".whl"):
            continue

        try:
            distribution, version, build, tags = (
                parse_wheel_filename(asset_name)
            )
        except Exception as exc:
            print(
                "Skipping invalid wheel:",
                asset_name,
                repr(exc),
            )
            continue

        matching_tags = (
            set(tags)
            .intersection(compatible_tags)
        )

        if not matching_tags:
            continue

        name_lower = asset_name.lower()

        score = 0

        # Prefer CUDA wheels.
        if "cuda" in name_lower:
            score += 100

        if "cu12" in name_lower:
            score += 50

        if "cu11" in name_lower:
            score += 40

        # Prefer Linux x86_64.
        if "linux" in name_lower:
            score += 20

        if "x86_64" in name_lower:
            score += 20

        if "amd64" in name_lower:
            score += 20

        # Prefer newer release position.
        score += (
            len(releases) - release_index
        )

        candidates.append(
            {
                "score": score,
                "release": release_name,
                "name": asset_name,
                "url": asset_url,
                "tags": [
                    str(tag)
                    for tag in matching_tags
                ],
            }
        )


print("=" * 80)
print(
    "COMPATIBLE WHEELS FOUND:",
    len(candidates),
)
print("=" * 80)


if not candidates:

    print()
    print(
        "NO COMPATIBLE JAMEPENG WHEEL FOUND."
    )
    print()

    print("Python:", sys.version)
    print(
        "Machine:",
        platform.machine(),
    )

    print()
    print(
        "Available JamePeng wheel assets:"
    )

    for release in releases:

        release_name = (
            release.get("name")
            or release.get("tag_name")
            or "unknown"
        )

        print()
        print(
            "RELEASE:",
            release_name,
        )

        for asset in release.get(
            "assets",
            [],
        ):

            name = asset.get(
                "name",
                "",
            )

            if name.endswith(".whl"):
                print(
                    "  ",
                    name,
                )

    raise RuntimeError(
        "No compatible "
        "llama-cpp-python wheel."
    )


# ============================================================
# SELECT BEST WHEEL
# ============================================================

candidates.sort(
    key=lambda item: item["score"],
    reverse=True,
)

print("Best candidates:")

for candidate in candidates[:10]:
    print(
        candidate["score"],
        candidate["release"],
        candidate["name"],
    )


selected = candidates[0]

print("=" * 80)
print("SELECTED LLAMA-CPP WHEEL")
print("=" * 80)

print(
    "Release:",
    selected["release"],
)

print(
    "File:",
    selected["name"],
)

print(
    "URL:",
    selected["url"],
)

print(
    "Matching tags:",
    selected["tags"],
)

print("=" * 80)


# ============================================================
# DOWNLOAD WHEEL
# ============================================================

wheel_path = os.path.join(
    tempfile.gettempdir(),
    selected["name"],
)

download_request = urllib.request.Request(
    selected["url"],
    headers={
        "User-Agent": "ComfyUI-Docker-Build",
        "Accept": "application/octet-stream",
    },
)

print(
    "Downloading:",
    selected["name"],
)

try:

    with urllib.request.urlopen(
        download_request,
        timeout=300,
    ) as response:

        with open(
            wheel_path,
            "wb",
        ) as output:

            while True:

                chunk = response.read(
                    1024 * 1024
                )

                if not chunk:
                    break

                output.write(chunk)

except Exception as exc:

    print(
        "Wheel download failed:",
        repr(exc),
    )

    raise


print(
    "Wheel downloaded:",
    wheel_path,
)


# ============================================================
# INSTALL WHEEL
# ============================================================

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

print("=" * 80)
print(
    "LLAMA-CPP-PYTHON INSTALLATION: OK"
)
print("=" * 80)
PY


# ============================================================
# 7. VERIFY LLAMA-CPP-PYTHON
#
# IMPORTANT:
# This check DOES NOT import ComfyUI.
# Therefore it does not require an NVIDIA driver
# during Docker build.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import sys

print("=" * 80)
print("VERIFYING LLAMA-CPP-PYTHON")
print("=" * 80)

import llama_cpp

print(
    "llama_cpp import: OK"
)

print(
    "llama_cpp path:",
    llama_cpp.__file__,
)

print(
    "llama_cpp version:",
    getattr(
        llama_cpp,
        "__version__",
        "unknown",
    ),
)

from llama_cpp import Llama

print(
    "Llama class: OK"
)


# Check standard vision handlers.
from llama_cpp.llama_chat_format import (
    Llava15ChatHandler,
    Llava16ChatHandler,
    MoondreamChatHandler,
    NanoLlavaChatHandler,
    Llama3VisionAlphaChatHandler,
    MiniCPMv26ChatHandler,
)

print(
    "Vision handlers: OK"
)


# Qwen3.5 is required by the workflow.
try:

    from llama_cpp.llama_chat_format import (
        Qwen35ChatHandler
    )

    print(
        "Qwen35ChatHandler: OK"
    )

except ImportError as exc:

    print(
        "Qwen35ChatHandler is missing!"
    )

    print(
        "Import error:",
        repr(exc),
    )

    raise


print("=" * 80)
print(
    "LLAMA-CPP-PYTHON CHECK: OK"
)
print("=" * 80)
PY


# ============================================================
# 8. STATIC CHECK OF CUSTOM NODE
#
# DO NOT IMPORT nodes.py HERE.
#
# ComfyUI's model_management.py initializes CUDA when imported.
# GitHub Actions has no NVIDIA driver.
#
# Instead we parse nodes.py and verify that all required
# NODE_CLASS_MAPPINGS names exist in the source.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import ast
import os

node_file = (
    "/default-comfyui-bundle/ComfyUI/"
    "custom_nodes/ComfyUI-llama-cpp_vlm/"
    "nodes.py"
)

print("=" * 80)
print("STATIC CHECK: ComfyUI-llama-cpp_vlm")
print("=" * 80)

if not os.path.isfile(node_file):
    raise RuntimeError(
        "nodes.py not found"
    )

print(
    "nodes.py:",
    node_file,
)

with open(
    node_file,
    "r",
    encoding="utf-8",
) as f:
    source = f.read()

print(
    "Source size:",
    len(source),
    "bytes",
)

tree = ast.parse(
    source,
    filename=node_file,
)

required_nodes = [
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
    "llama_cpp_parameters",
    "llama_cpp_unload_model",
    "llama_cpp_clean_states",
    "parse_json_node",
    "json_to_bbox",
    "bbox_to_segs",
    "bbox_to_mask",
    "bboxes_to_bbox",
    "remove_code_block",
    "PromptEnhancerPreset",
    "llama_cpp_text_encoder",
]

source_names = set()

for node in ast.walk(tree):

    if isinstance(
        node,
        ast.Name,
    ):
        source_names.add(node.id)

    elif isinstance(
        node,
        ast.Constant,
    ):
        if isinstance(
            node.value,
            str,
        ):
            source_names.add(
                node.value
            )


print("=" * 80)
print("Checking required node names")
print("=" * 80)

missing = []

for node_name in required_nodes:

    if node_name in source_names:

        print(
            "OK:",
            node_name,
        )

    else:

        missing.append(
            node_name
        )

if missing:

    print()
    print(
        "Missing node names:"
    )

    for name in missing:
        print(
            "  ",
            name,
        )

    raise RuntimeError(
        "Some required Llama nodes "
        "were not found in nodes.py"
    )

print("=" * 80)
print(
    "CUSTOM NODE STATIC CHECK: OK"
)
print("=" * 80)
PY


# ============================================================
# 9. CHECK CUSTOM NODE FILE STRUCTURE
# ============================================================

RUN set -eux; \
    cd "${COMFYUI_PATH}/custom_nodes/ComfyUI-llama-cpp_vlm"; \
    test -f nodes.py; \
    test -f __init__.py; \
    test -d support; \
    test -f support/cqdm.py; \
    test -f support/gguf_layers.py; \
    test -f support/prompt_enhancer_preset.py; \
    echo "ComfyUI-llama-cpp_vlm file structure: OK"


# ============================================================
# 10. CREATE LLM MODEL DIRECTORY
# ============================================================

RUN set -eux; \
    mkdir -p "${COMFYUI_PATH}/models/LLM"; \
    mkdir -p "${COMFYUI_PATH}/workflows"; \
    chmod -R 777 \
        "${COMFYUI_PATH}/models/LLM" || true; \
    chmod -R 777 \
        "${COMFYUI_PATH}/workflows" || true


# ============================================================
# 11. COPY CARUSEL WORKFLOW
# ============================================================

COPY CARUSEL.json /tmp/CARUSEL.json


# ============================================================
# 12. VALIDATE CARUSEL.JSON
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import json

workflow_file = "/tmp/CARUSEL.json"

print("=" * 80)
print("VALIDATING CARUSEL.json")
print("=" * 80)

with open(
    workflow_file,
    "r",
    encoding="utf-8",
) as f:
    workflow = json.load(f)

print(
    "JSON syntax: OK"
)

if not isinstance(
    workflow,
    dict,
):
    raise RuntimeError(
        "Workflow root is not an object"
    )

print(
    "Workflow nodes:",
    len(workflow),
)

required_types = {
    "llama_cpp_parameters",
    "llama_cpp_model_loader",
    "llama_cpp_instruct_adv",
}

found_types = set()

for node_id, node in workflow.items():

    if not isinstance(
        node,
        dict,
    ):
        continue

    class_type = node.get(
        "class_type"
    )

    if class_type:
        found_types.add(
            class_type
        )

print("=" * 80)
print("Checking Llama workflow nodes")
print("=" * 80)

for required in sorted(
    required_types
):

    if required in found_types:

        print(
            "FOUND:",
            required,
        )

    else:

        raise RuntimeError(
            "Required workflow node "
            f"missing: {required}"
        )

print("=" * 80)
print(
    "CARUSEL.json VALIDATION: OK"
)
print("=" * 80)
PY


# ============================================================
# 13. INSTALL WORKFLOW INTO COMFYUI
# ============================================================

RUN set -eux; \
    cp \
        /tmp/CARUSEL.json \
        "${COMFYUI_PATH}/workflows/CARUSEL.json"; \
    rm -f /tmp/CARUSEL.json


# ============================================================
# 14. FINAL IMAGE CHECK
#
# Again: NO ComfyUI import here.
# NO torch.cuda.current_device().
# NO NVIDIA driver required during build.
# ============================================================

RUN set -eux; \
    python3 - <<'PY'
import os
import sys

print("=" * 80)
print("FINAL DOCKER IMAGE CHECK")
print("=" * 80)

print(
    "Python:",
    sys.version,
)

comfyui = (
    "/default-comfyui-bundle/ComfyUI"
)

llama_node = (
    comfyui
    + "/custom_nodes/"
    + "ComfyUI-llama-cpp_vlm"
)

llm_dir = (
    comfyui
    + "/models/LLM"
)

workflow = (
    comfyui
    + "/workflows/CARUSEL.json"
)

checks = {
    "ComfyUI": os.path.isdir(comfyui),
    "Llama custom node": os.path.isdir(llama_node),
    "LLM directory": os.path.isdir(llm_dir),
    "CARUSEL workflow": os.path.isfile(workflow),
}

for name, result in checks.items():

    print(
        f"{name}:",
        "OK" if result else "FAIL",
    )

    if not result:
        raise RuntimeError(
            f"Final check failed: {name}"
        )

import llama_cpp

print(
    "llama_cpp:",
    getattr(
        llama_cpp,
        "__version__",
        "unknown",
    ),
)

print("=" * 80)
print(
    "DOCKER IMAGE BUILD CHECK: OK"
)
print("=" * 80)
PY


# ============================================================
# 15. WORKDIR
# ============================================================

WORKDIR ${COMFYUI_PATH}
