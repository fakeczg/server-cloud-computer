#!/bin/bash
# Strict mode
set -euo pipefail
IFS=$'\n\t'

# ========================
#  参数检查
# ========================
if [[ $# -ne 1 ]]; then
	echo "❌ ERROR: Missing parameter."
	echo "Usage: $0 <DEST_BASE_DIRECTORY>"
	echo "Example:"
	echo "  $0 /data/temp/update_device_so"
	exit 1
fi

DEST_BASE="$1" # 目标根目录由用户传入
SRC_BASE="hdf/device_pd2508_laptop"

DEST_LIB64="$DEST_BASE/lib64"
DEST_CHIPSETSDK="$DEST_BASE/chipsetsdk"

DEST_LIB64_FILES=(
	"libdisplay_composer_vendor.z.so"
	"libdisplay_composer_vdi_impl.z.so"
	"libdisplay_gfx.z.so"
)

DEST_CHIPSETSDK_FILES=(
	"libdisplay_buffer_vdi_impl.z.so"
	"libdisplay_buffer_vendor.z.so"
)

# ========================
# 函数定义
# ========================

check_local_sources() {
	echo "=== 🔍 Checking local source files ==="
	for lib in "${DEST_LIB64_FILES[@]}" "${DEST_CHIPSETSDK_FILES[@]}"; do
		src_path="$SRC_BASE/$lib"
		if [[ ! -f "$src_path" ]]; then
			echo "❌ ERROR: Missing local file: $src_path"
			exit 1
		fi
		echo "✅ Found: $src_path"
	done
}

prepare_dirs() {
	echo "=== 📁 Creating target directories ==="
	mkdir -p "$DEST_LIB64"
	mkdir -p "$DEST_CHIPSETSDK"
	echo "✔️ Directories ready:"
	echo "   $DEST_LIB64"
	echo "   $DEST_CHIPSETSDK"
}

local_delete() {
	echo "=== 🧹 Removing old files ==="
	for lib in "${DEST_LIB64_FILES[@]}"; do
		rm -f "$DEST_LIB64/$lib" || true
		echo "🗑️ Removed: $DEST_LIB64/$lib"
	done

	for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
		rm -f "$DEST_CHIPSETSDK/$lib" || true
		echo "🗑️ Removed: $DEST_CHIPSETSDK/$lib"
	done
}

local_copy() {
	echo "=== 📤 Copying new libraries ==="
	for lib in "${DEST_LIB64_FILES[@]}"; do
		cp "$SRC_BASE/$lib" "$DEST_LIB64/$lib"
		chmod 644 "$DEST_LIB64/$lib"
		echo "✅ Copied: $lib → $DEST_LIB64"
	done

	for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
		cp "$SRC_BASE/$lib" "$DEST_CHIPSETSDK/$lib"
		chmod 644 "$DEST_CHIPSETSDK/$lib"
		echo "✅ Copied: $lib → $DEST_CHIPSETSDK"
	done
}

verify_files() {
	echo "=== 🔎 Verifying copied files ==="
	for lib in "${DEST_LIB64_FILES[@]}"; do
		[[ -f "$DEST_LIB64/$lib" ]] || {
			echo "❌ Missing: $DEST_LIB64/$lib"
			exit 1
		}
		echo "✔️ OK: $DEST_LIB64/$lib"
	done
	for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
		[[ -f "$DEST_CHIPSETSDK/$lib" ]] || {
			echo "❌ Missing: $DEST_CHIPSETSDK/$lib"
			exit 1
		}
		echo "✔️ OK: $DEST_CHIPSETSDK/$lib"
	done
}

main() {
	echo "===== 🚀 Copying Display Libraries ====="
	echo "DEST_BASE = $DEST_BASE"

	check_local_sources
	prepare_dirs
	local_delete
	local_copy
	verify_files

	echo "===== 🎉 Completed: all libs copied under $DEST_BASE ====="
}

main
