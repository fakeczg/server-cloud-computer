#!/bin/bash
# Strict mode
set -euo pipefail
IFS=$'\n\t'

# === 配置 ===
SRC_BASE="hdf/device_tengrui_d"

DEST_LIB64_FILES=(
    "libdisplay_composer_vendor.z.so"
    "libdisplay_composer_vdi_impl.z.so"
    "libdisplay_gfx.z.so"
)

DEST_CHIPSETSDK_FILES=(
    "libdisplay_buffer_vdi_impl.z.so"
    "libdisplay_buffer_vendor.z.so"
)

# === 参数校验 ===
if [[ $# -ne 1 ]]; then
    echo "❌ Usage: $0 <output_folder>"
    exit 1
fi

OUTPUT_DIR="$1"
DEST_LIB64="$OUTPUT_DIR/lib64"
DEST_CHIPSETSDK="$DEST_LIB64/chipsetsdk"

echo "📦 Packaging display libs into: $OUTPUT_DIR"

# === 创建目录结构 ===
mkdir -p "$DEST_LIB64"
mkdir -p "$DEST_CHIPSETSDK"

# === 拷贝 lib64 文件 ===
for lib in "${DEST_LIB64_FILES[@]}"; do
    src="$SRC_BASE/$lib"
    dst="$DEST_LIB64/$lib"
    if [[ ! -f "$src" ]]; then
        echo "❌ Missing source file: $src"
        exit 1
    fi
    cp -a "$src" "$dst"
    echo "✅ Copied: $src -> $dst"
done

# === 拷贝 chipsetsdk 文件 ===
for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
    src="$SRC_BASE/$lib"
    dst="$DEST_CHIPSETSDK/$lib"
    if [[ ! -f "$src" ]]; then
        echo "❌ Missing source file: $src"
        exit 1
    fi
    cp -a "$src" "$dst"
    echo "✅ Copied: $src -> $dst"
done

echo "🎉 Done. Files packaged in: $OUTPUT_DIR"
