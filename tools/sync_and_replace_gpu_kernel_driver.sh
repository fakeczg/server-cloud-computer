#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# 用法:
#   ./sync_and_replace_gpu_kernel_driver.sh <SRC_DIR> <KERNEL_ROOT> <GPU_NAME>
# 例子:
#   ./sync_and_replace_gpu_kernel_driver.sh \
#     /home/you/android_d3000m_graphic_driver \
#     /home/you/android_common_kernel_6.6 \
#     FTG340

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <SRC_DIR> <KERNEL_ROOT> <GPU_NAME>"
  exit 1
fi

SRC_DIR="$(realpath -m "$1")"
KERNEL_ROOT="$(realpath -m "$2")"
GPU_NAME="$3"

# 目标路径
TARGET_BASE="$KERNEL_ROOT/drivers/gpu/drm/phytium/$GPU_NAME"
TARGET_ARCH="$TARGET_BASE/arch"
TARGET_HAL="$TARGET_BASE/hal"

echo "[Info] SRC_DIR     = $SRC_DIR"
echo "[Info] KERNEL_ROOT = $KERNEL_ROOT"
echo "[Info] TARGET_BASE = $TARGET_BASE"

# 基本检查
for d in "$SRC_DIR/arch" "$SRC_DIR/hal"; do
  [[ -d "$d" ]] || { echo "[Error] missing: $d"; exit 2; }
done

# 依赖检查
for dep in rsync perl python3; do
  command -v "$dep" >/dev/null || { echo "[Error] need: $dep"; exit 3; }
done

# ------------------------------
# 清理并建目录（只清理要覆盖的子目录）
# ------------------------------
echo "[Step] Prepare target dirs ..."

mkdir -p "$TARGET_BASE" "$TARGET_BASE/tools/bin"

# ---- arch ----
if [[ -d "$SRC_DIR/arch/XAQ2" ]]; then
  rm -rf "$TARGET_ARCH/XAQ2"
  mkdir -p "$TARGET_ARCH/XAQ2"
else
  rm -rf "$TARGET_ARCH"
  mkdir -p "$TARGET_ARCH"
fi

# ---- hal ----
rm -rf "$TARGET_HAL/os/linux/kernel" \
       "$TARGET_HAL/kernel" \
       "$TARGET_HAL/security_v1" \
       "$TARGET_HAL/inc"

mkdir -p "$TARGET_HAL/os/linux/kernel" "$TARGET_HAL"

# ---- tools ----
mkdir -p "$TARGET_BASE/tools/bin"

# ------------------------------
# 同步源码
# ------------------------------
echo "[Step] Sync sources ..."
if [[ -d "$SRC_DIR/arch/XAQ2" ]]; then
  rsync -a --delete "$SRC_DIR/arch/XAQ2/" "$TARGET_ARCH/XAQ2/"
else
  rsync -a --delete "$SRC_DIR/arch/"     "$TARGET_ARCH/"
fi

[[ -d "$SRC_DIR/hal/os/linux/kernel" ]] && rsync -a "$SRC_DIR/hal/os/linux/kernel/" "$TARGET_HAL/os/linux/kernel/"
for sub in kernel security_v1 inc; do
  [[ -d "$SRC_DIR/hal/$sub" ]] && rsync -a "$SRC_DIR/hal/$sub/" "$TARGET_HAL/$sub/"
done

# ------------------------------
# 替换逻辑（版权头+行内替换）
# ------------------------------
echo "[Step] Start replacements ..."

declare -a REPL=(
  "Copyright (c) 2014 - 2025 Vivante Corporation==Copyright (c) 2025, Phytium Technology Co., Ltd."
  "Copyright (C) 2014 - 2025 Vivante Corporation==Copyright (c) 2025, Phytium Technology Co., Ltd."
  "galcore==ftg340"
  "Galcore==ftg340"
  "GALCORE==FTG340"
  "VIVANTE_PROFILER==PHYTIUM_PROFILER"
)

PY="$(mktemp)"
trap 'rm -f "$PY"' EXIT
cat >"$PY"<<'PY'
import io,sys,re
NEW = r'''/****************************************************************************
*
* Copyright (c) 2025 Phytium Technology Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*
*****************************************************************************/'''
path = sys.argv[1]
with io.open(path, 'r', encoding='utf-8', errors='replace') as f:
    data = f.read()
head = data[:8192]
m = re.match(r'^\s*/\*[\s\S]*?\*/', head)
if m and re.search(r'Vivante', m.group(0), flags=re.I):
    new = data.replace(m.group(0), NEW, 1)
    if new != data:
        with io.open(path, 'w', encoding='utf-8', errors='replace') as f:
            f.write(new)
        print(path)
        sys.exit(0)
sys.exit(1)
PY

changed_files=0
header_changed=0

mapfile -d '' -t files < <(
  find "$TARGET_BASE" -type f \( \
      -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.S' -o \
      -name 'Kbuild' -o -name 'Makefile' -o -name '*.mk' -o -name 'Kconfig' -o \
      -name '*.txt' \
    \) -print0
)

for f in "${files[@]}"; do
  touched=0

  if python3 "$PY" "$f" >/dev/null 2>&1; then
    echo "  [HDR] $f"
    touched=1
    ((header_changed+=1))
  fi

  for pair in "${REPL[@]}"; do
    L="${pair%%==*}"; R="${pair##*==}"
    if grep -qF -- "$L" "$f"; then
      perl -0777 -i -pe "s/\\Q$L\\E/$R/g" "$f"
      touched=1
    fi
  done

  if [[ $touched -eq 1 ]]; then
    echo "  [MOD] $f"
    ((changed_files+=1))
  fi
done

echo "[Done] replacements finished."
echo "       headers changed : $header_changed"
echo "       files modified  : $changed_files"
echo "Target: $TARGET_BASE"

if [[ $changed_files -eq 0 && $header_changed -eq 0 ]]; then
  echo "[Warn] No files were changed. Check patterns and source contents." >&2
fi

