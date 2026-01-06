 #!/bin/bash
    # Strict mode
    set -euo pipefail
    IFS=$'\n\t'

    SRC_BASE="hdf/device_tengrui_d"
    DEST_VENDOR="/mnt/vendor"
    DEST_LIB64="$DEST_VENDOR/lib64"
    DEST_CHIPSETSDK="$DEST_VENDOR/lib64/chipsetsdk"

    DEST_LIB64_FILES=(
        "libdisplay_composer_vendor.z.so"
        "libdisplay_composer_vdi_impl.z.so"
        "libdisplay_gfx.z.so"
    )

    DEST_CHIPSETSDK_FILES=(
        "libdisplay_buffer_vdi_impl.z.so"
        "libdisplay_buffer_vendor.z.so"
    )

    # 检查 vendor 是否挂载并尝试挂载为 rw
    mount_vendor_rw() {
        echo "=== 🔧 Checking /mnt/vendor mount status ==="
        mountpoint "$DEST_VENDOR" >/dev/null || {
            echo "❌ ERROR: $DEST_VENDOR is not a mount point. Please mount it before running this script."
            exit 1
        }

        mount_info=$(mount | grep "$DEST_VENDOR" || true)
        if echo "$mount_info" | grep -q "ro,"; then
            echo "🔄 /mnt/vendor is read-only, attempting to remount as rw..."
            sudo mount -o remount,rw "$DEST_VENDOR" || {
                echo "❌ ERROR: Failed to remount $DEST_VENDOR as rw"
                exit 1
            }
            echo "✅ Remounted $DEST_VENDOR as rw"
        else
            echo "✅ $DEST_VENDOR already mounted as read-write"
        fi
    }

    # 检查源文件是否存在
    precheck() {
        echo "=== 🔍 Checking local source files ==="
        for lib in "${DEST_LIB64_FILES[@]}" "${DEST_CHIPSETSDK_FILES[@]}"; do
            src_path="$SRC_BASE/$lib"
            if [[ ! -f "$src_path" ]]; then
                echo "❌ ERROR: Source library not found: $src_path"
                exit 1
            fi
            echo "✅ Found: $src_path"
        done
    }

    # 清理旧文件
    clean_old_libs() {
        echo "=== 🧹 Cleaning old libraries ==="
        for lib in "${DEST_LIB64_FILES[@]}"; do
            rm -f "$DEST_LIB64/$lib" && echo "🗑️ Removed: $DEST_LIB64/$lib" || echo "Skip: $DEST_LIB64/$lib"
        done
        for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
            rm -f "$DEST_CHIPSETSDK/$lib" && echo "🗑️ Removed: $DEST_CHIPSETSDK/$lib" || echo "Skip: $DEST_CHIPSETSDK/$lib"
        done
    }

    # 部署新文件
    deploy_new_libs() {
        echo "=== 🚀 Deploying new libraries ==="

        mkdir -p "$DEST_LIB64" "$DEST_CHIPSETSDK"

        for lib in "${DEST_LIB64_FILES[@]}"; do
            cp -a "$SRC_BASE/$lib" "$DEST_LIB64/"
            chmod 644 "$DEST_LIB64/$lib"
            echo "✅ Copied to $DEST_LIB64/$lib"
        done

        for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
            cp -a "$SRC_BASE/$lib" "$DEST_CHIPSETSDK/"
            chmod 644 "$DEST_CHIPSETSDK/$lib"
            echo "✅ Copied to $DEST_CHIPSETSDK/$lib"
        done
    }

    # 验证部署结果
    verify_deployment() {
        echo "=== ✅ Verifying deployment ==="
        for lib in "${DEST_LIB64_FILES[@]}"; do
            file="$DEST_LIB64/$lib"
            [[ -f "$file" ]] || { echo "❌ Missing: $file"; exit 1; }
            echo "✔️ Found: $file | Perm: $(stat -c '%A' "$file")"
        done

        for lib in "${DEST_CHIPSETSDK_FILES[@]}"; do
            file="$DEST_CHIPSETSDK/$lib"
            [[ -f "$file" ]] || { echo "❌ Missing: $file"; exit 1; }
            echo "✔️ Found: $file | Perm: $(stat -c '%A' "$file")"
        done
    }

    # 主流程
    main() {
        echo "===== 📦 Starting Phytium Display Library Deployment ====="
        echo "System: $(uname -a)"
        echo "Bash: $BASH_VERSION"
        echo "Disk Usage at $DEST_VENDOR:"
        df -h "$DEST_VENDOR" | tail -n 1

        mount_vendor_rw
        precheck
        clean_old_libs
        deploy_new_libs
        verify_deployment

        echo "===== ✅ Deployment Completed Successfully ====="
    }

    # 执行
    main 2>&1 | tee -a /var/log/phytium_display_lib_deploy.log
