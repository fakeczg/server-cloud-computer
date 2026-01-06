#!/bin/bash
# Strict mode
set -euo pipefail
IFS=$'\n\t'

# === 配置 ===
SRC_BASE="hdf/device_pd2508_laptop"
DEST_LIB64="/vendor/lib64"
DEST_CHIPSETSDK="/vendor/lib64/chipsetsdk"

DEST_LIB64_FILES=(
    "libdisplay_composer_vendor.z.so"
    "libdisplay_composer_vdi_impl.z.so"
    "libdisplay_gfx.z.so"
)

DEST_CHIPSETSDK_FILES=(
    "libdisplay_buffer_vdi_impl.z.so"
    "libdisplay_buffer_vendor.z.so"
)

# === 函数定义 ===

# 1. 检查源文件存在
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

# 2. 尝试 remount /vendor 为可写
prepare_vendor_rw() {
    echo "=== 🔧 Remounting /vendor as read-write (rw) ==="
    current_mount_info=$(hdc shell "mount | grep '/vendor'" || true)
    echo "$current_mount_info"

    if echo "$current_mount_info" | grep -q "ro,"; then
        echo "🔄 /vendor is currently read-only, attempting to remount..."
        hdc shell "mount -o remount,rw /vendor" || {
            echo "❌ ERROR: Failed to remount /vendor as rw. Permission denied or secure boot may prevent this."
            exit 1
        }
        echo "✅ Remounted /vendor as rw"
    else
        echo "✅ /vendor already writable"
    fi
}

# 3. 删除设备上的旧文件
remote_delete() {
    echo "=== 🧹 Deleting old libraries on device ==="
    for lib in "${DEST_LIB64_FILES[@]}"; do
        hdc shell "rm -f $DEST_LIB64/$lib" || true
        echo "🗑️ Removed: $DEST_LIB64/$lib"
    done
    for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
        hdc shell "rm -f $DEST_CHIPSETSDK/$lib" || true
        echo "🗑️ Removed: $DEST_CHIPSETSDK/$lib"
    done
}

# 4. 发送新文件并设置权限
send_files() {
    echo "=== 📤 Sending new libraries to device ==="

    for lib in "${DEST_LIB64_FILES[@]}"; do
        src_path="$SRC_BASE/$lib"
        dst_path="$DEST_LIB64/$lib"
        hdc file send "$src_path" "$dst_path"
        hdc shell "chmod 644 $dst_path"
        echo "✅ Sent: $src_path -> $dst_path"
    done

    for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
        src_path="$SRC_BASE/$lib"
        dst_path="$DEST_CHIPSETSDK/$lib"
        hdc file send "$src_path" "$dst_path"
        hdc shell "chmod 644 $dst_path"
        echo "✅ Sent: $src_path -> $dst_path"
    done
}

# 5. 验证远程部署结果
verify_remote_files() {
    echo "=== ✅ Verifying deployed libraries on device ==="
    for lib in "${DEST_LIB64_FILES[@]}"; do
        remote_path="$DEST_LIB64/$lib"
        hdc shell "[ -f $remote_path ]" || { echo "❌ Missing: $remote_path"; exit 1; }
        echo "✔️ Verified: $remote_path"
    done
    for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
        remote_path="$DEST_CHIPSETSDK/$lib"
        hdc shell "[ -f $remote_path ]" || { echo "❌ Missing: $remote_path"; exit 1; }
        echo "✔️ Verified: $remote_path"
    done
}

# 主流程
main() {
    echo "===== 🚀 Starting HDC Library Deployment ====="
    echo "System: $(uname -a)"
    echo "Bash version: $BASH_VERSION"
    echo "HDC connected device: $(hdc list targets | grep -v 'List' || echo '❌ No device')"

    prepare_vendor_rw
    check_local_sources
    remote_delete
    send_files
    verify_remote_files

    echo "===== 🎉 HDC Deployment Completed Successfully ====="
}

# 执行并保存日志
main 2>&1 | tee -a ./hdc_display_lib_deploy.log

