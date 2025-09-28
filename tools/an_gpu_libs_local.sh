#!/usr/bin/env bash
set -euo pipefail

# =========================================
# an_gpu_libs_local.sh
# 仅进行本地操作：列时间、复制、删除；支持复制/删除到 Gerrit gpu_lib 目录（target_aarch64 / target_armv7-a）
# 不使用 adb，也不需要选择 cp|adb 模式
# =========================================

DRY_RUN=0

usage() {
  cat <<'EOF'
用法：
  1) 列出来源目录文件时间：
     an_gpu_libs_local.sh times-src <SRC_ROOT>
     ex: ./an_gpu_libs_local.sh  times-src /home/chenzigui/src/Android/AN13/src/aosp/out/target/product/pd2508

  2) 列出目标目录（镜像 vendor 结构）文件时间：
     an_gpu_libs_local.sh times-dst <DST_ROOT>

  3) 复制到一个目标根目录（按原始 vendor 目录结构铺开）：
     an_gpu_libs_local.sh copy-root <SRC_ROOT> <DST_ROOT> [--dry-run]

  4) 在一个目标根目录中删除这些库（按原始 vendor 目录结构删除）：
     an_gpu_libs_local.sh delete-root <DST_ROOT> [--arch aarch64|armv7-a] [--all] [--dry-run]
     说明：默认按 --arch 选择 64/32 位清单；加 --all 同时删除两套清单

  4.5) 在来源根目录 SRC_ROOT 中删除这些库（按原始 vendor 目录结构删除）：
     an_gpu_libs_local.sh delete-src <SRC_ROOT> [--arch aarch64|armv7-a] [--all] [--dry-run]
     ./an_gpu_libs_local.sh  delete-src  /home/chenzigui/src/Android/AN13/src/aosp/out/target/product/pd2508 --all --dry-run
     ./an_gpu_libs_local.sh  delete-src  /home/chenzigui/src/Android/AN13/src/aosp/out/target/product/pd2508 --all

  5) 复制到 Gerrit 仓库 gpu_lib 目录（扁平放入 target_*/）：
     an_gpu_libs_local.sh copy-gerrit <SRC_ROOT> <GPU_LIB_DIR> --arch aarch64|armv7-a [--dry-run]
     例：GPU_LIB_DIR 为
         ~/src/Android/AN13/src/device/gerrit/e2000_android13_device/device_phytium/pd2508/gpu/gpu_lib

  6) 在 Gerrit 仓库 gpu_lib 的 target_*/ 目录删除对应库：
     an_gpu_libs_local.sh delete-gerrit <GPU_LIB_DIR> --arch aarch64|armv7-a [--dry-run]

  7) 列出 Gerrit gpu_lib 目录里库文件的时间（扁平 target_*/）：
     an_gpu_libs_local.sh times-gerrit <GPU_LIB_DIR> [--arch aarch64|armv7-a] [--all]

说明：
  - <SRC_ROOT> 和 <DST_ROOT> 为根目录，脚本会在其下按 FILES_* 中的相对路径进行取/放。
  - copy-gerrit / delete-gerrit / times-gerrit 为扁平（仅文件名）操作：target_aarch64/ 与 target_armv7-a/ 仅放 .so 文件。
  - 若目标目录无写权限，将自动尝试 sudo。
  - 使用 --dry-run 可先预演不落盘。

EOF
}

# -----------------------------
# 文件清单（64 位 / 32 位）
# -----------------------------
FILES_64=(
  "vendor/lib64/egl/libEGL_FTG340.so"
  "vendor/lib64/egl/libGLESv1_CM_FTG340.so"
  "vendor/lib64/egl/libGLESv2_FTG340.so"
  "vendor/lib64/hw/gralloc.FTG340.so"
  "vendor/lib64/libdrm_android.so"
  "vendor/lib64/libdrm_ftg340.so"
  "vendor/lib64/libdrm_vivante.so"
  "vendor/lib64/libGAL.so"
  "vendor/lib64/libGLSLC.so"
  "vendor/lib64/libVSC.so"
)

FILES_32=(
  "vendor/lib/egl/libEGL_FTG340.so"
  "vendor/lib/egl/libGLESv1_CM_FTG340.so"
  "vendor/lib/egl/libGLESv2_FTG340.so"
  "vendor/lib/hw/gralloc.FTG340.so"
  "vendor/lib/libdrm_android.so"
  "vendor/lib/libdrm_ftg340.so"
  "vendor/lib/libdrm_vivante.so"
  "vendor/lib/libGAL.so"
  "vendor/lib/libGLSLC.so"
  "vendor/lib/libVSC.so"
)

# -----------------------------
# 工具函数
# -----------------------------
need_sudo_mv() {
  local dst="$1"
  local dir
  dir=$(dirname "$dst")
  if [ ! -d "$dir" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[DRY-RUN] mkdir -p '$dir'"
      return 1  # 不创建，后续也不 sudo
    else
      mkdir -p "$dir" || return 0
    fi
  fi

  if [ -w "$dir" ]; then
    return 1  # 不需要 sudo
  else
    return 0  # 需要 sudo
  fi
}

print_file_time() {
  local f="$1"
  if [ -f "$f" ]; then
    local t
    t=$(stat --format='%y' "$f")
    echo -e "File: $f \t Modification Time: $t"
  else
    echo "File not found: $f"
  fi
}

print_times_for_list() {
  local root="$1"; shift
  local -n arr="$1"
  echo "== 列出 $root 下文件时间 =="
  for rel in "${arr[@]}"; do
    print_file_time "$root/$rel"
  done
}

copy_one_file() {
  local src="$1" dst="$2"
  local base tmpdir tmpfile
  base=$(basename "$dst")
  tmpdir="/tmp/an_gpu_libs_tmp"
  tmpfile="$tmpdir/$base"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] cp -p '$src' '$tmpfile' && mv -> '$dst' (auto sudo if needed)"
    return 0
  fi

  mkdir -p "$tmpdir"
  cp -p "$src" "$tmpfile"

  if need_sudo_mv "$dst"; then
    echo "sudo mv '$tmpfile' '$dst'"
    sudo mv "$tmpfile" "$dst"
  else
    echo "mv '$tmpfile' '$dst'"
    mv "$tmpfile" "$dst"
  fi
}

remove_one_file() {
  local dst="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] rm -f '$dst' (auto sudo if needed)"
    return 0
  fi

  if [ -f "$dst" ]; then
    if need_sudo_mv "$dst"; then
      echo "sudo rm -f '$dst'"
      sudo rm -f "$dst"
    else
      echo "rm -f '$dst'"
      rm -f "$dst"
    fi
  else
    echo "Not exist: $dst"
  fi
}

flatten_copy_to_gerrit() {
  local src_root="$1" gpu_lib_dir="$2" arch="$3"
  local target_dir
  case "$arch" in
    aarch64)  target_dir="$gpu_lib_dir/target_aarch64" ;;
    armv7-a)  target_dir="$gpu_lib_dir/target_armv7-a" ;;
    *) echo "未知架构：$arch（应为 aarch64 或 armv7-a）"; exit 1 ;;
  esac

  local -n arr=$([ "$arch" = "aarch64" ] && echo FILES_64 || echo FILES_32)

  echo "== 复制到 Gerrit 目录：$target_dir =="
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] mkdir -p '$target_dir'"
  else
    mkdir -p "$target_dir"
  fi

  for rel in "${arr[@]}"; do
    local src="$src_root/$rel"
    local base
    base=$(basename "$rel")
    local dst="$target_dir/$base"

    if [ -f "$src" ]; then
      echo "Copy: $src  ->  $dst"
      copy_one_file "$src" "$dst"
    else
      echo "Skip (missing): $src"
    fi
  done
}

flatten_delete_in_gerrit() {
  local gpu_lib_dir="$1" arch="$2"
  local target_dir
  case "$arch" in
    aarch64)  target_dir="$gpu_lib_dir/target_aarch64" ;;
    armv7-a)  target_dir="$gpu_lib_dir/target_armv7-a" ;;
    *) echo "未知架构：$arch（应为 aarch64 或 armv7-a）"; exit 1 ;;
  esac

  local -n arr=$([ "$arch" = "aarch64" ] && echo FILES_64 || echo FILES_32)

  echo "== 删除 Gerrit 目录中的库：$target_dir =="
  for rel in "${arr[@]}"; do
    local base
    base=$(basename "$rel")
    local dst="$target_dir/$base"
    remove_one_file "$dst"
  done
}

print_times_in_gerrit() {
  local gpu_lib_dir="$1" arch="$2"
  local target_dir
  case "$arch" in
    aarch64)  target_dir="$gpu_lib_dir/target_aarch64" ;;
    armv7-a)  target_dir="$gpu_lib_dir/target_armv7-a" ;;
    *) echo "未知架构：$arch（应为 aarch64 或 armv7-a）"; exit 1 ;;
  esac

  local -n arr=$([ "$arch" = "aarch64" ] && echo FILES_64 || echo FILES_32)
  echo "== 列出 Gerrit $target_dir 中文件时间（扁平） =="
  for rel in "${arr[@]}"; do
    local base
    base=$(basename "$rel")
    print_file_time "$target_dir/$base"
  done
}

copy_to_root_with_layout() {
  local src_root="$1" dst_root="$2"
  echo "== 按 vendor 目录结构复制到：$dst_root =="

  for rel in "${FILES_64[@]}"; do
    local src="$src_root/$rel"
    local dst="$dst_root/$rel"
    if [ -f "$src" ]; then
      echo "Copy: $src  ->  $dst"
      copy_one_file "$src" "$dst"
    else
      echo "Skip (missing): $src"
    fi
  done

  for rel in "${FILES_32[@]}"; do
    local src="$src_root/$rel"
    local dst="$dst_root/$rel"
    if [ -f "$src" ]; then
      echo "Copy: $src  ->  $dst"
      copy_one_file "$src" "$dst"
    else
      echo "Skip (missing): $src"
    fi
  done
}

delete_in_root_with_layout() {
  local dst_root="$1"
  local del64="$2" del32="$3"
  echo "== 按 vendor 目录结构删除：$dst_root =="

  if [ "$del64" -eq 1 ]; then
    for rel in "${FILES_64[@]}"; do
      remove_one_file "$dst_root/$rel"
    done
  fi

  if [ "$del32" -eq 1 ]; then
    for rel in "${FILES_32[@]}"; do
      remove_one_file "$dst_root/$rel"
    done
  fi
}

# -----------------------------
# 参数解析（支持 --dry-run / --arch / --all）
# -----------------------------
if [ $# -lt 1 ]; then
  usage; exit 1
fi

cmd="$1"; shift || true

ARCH=""
DEL_ALL=0

parse_common_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --arch)
        ARCH="${2:-}"; shift 2 || { echo "--arch 缺少取值"; exit 1; }
        ;;
      --all)
        DEL_ALL=1; shift ;;
      *)
        break ;;
    esac
  done
  REM_ARGS=("$@")
}

case "$cmd" in
  times-src)
    [ $# -ge 1 ] || { usage; exit 1; }
    SRC_ROOT="$1"
    echo "来源目录：$SRC_ROOT"
    print_times_for_list "$SRC_ROOT" FILES_64
    print_times_for_list "$SRC_ROOT" FILES_32
    ;;

  times-dst)
    [ $# -ge 1 ] || { usage; exit 1; }
    DST_ROOT="$1"
    echo "目标目录：$DST_ROOT"
    print_times_for_list "$DST_ROOT" FILES_64
    print_times_for_list "$DST_ROOT" FILES_32
    ;;

  copy-root)
    [ $# -ge 2 ] || { usage; exit 1; }
    SRC_ROOT="$1"; DST_ROOT="$2"; shift 2 || true
    parse_common_flags "$@"
    copy_to_root_with_layout "$SRC_ROOT" "$DST_ROOT"
    ;;

  delete-root)
    [ $# -ge 1 ] || { usage; exit 1; }
    DST_ROOT="$1"; shift || true
    parse_common_flags "$@"

    DEL64=0; DEL32=0
    if [ "$DEL_ALL" -eq 1 ]; then
      DEL64=1; DEL32=1
    else
      case "${ARCH:-}" in
        aarch64) DEL64=1 ;;
        armv7-a) DEL32=1 ;;
        "") echo "delete-root 需要指定 --arch aarch64|armv7-a 或者使用 --all"; exit 1 ;;
        *) echo "未知架构：$ARCH"; exit 1 ;;
      esac
    fi
    delete_in_root_with_layout "$DST_ROOT" "$DEL64" "$DEL32"
    ;;

  delete-src)
    [ $# -ge 1 ] || { usage; exit 1; }
    SRC_ROOT="$1"; shift || true
    parse_common_flags "$@"

    DEL64=0; DEL32=0
    if [ "$DEL_ALL" -eq 1 ]; then
      DEL64=1; DEL32=1
    else
      case "${ARCH:-}" in
        aarch64) DEL64=1 ;;
        armv7-a) DEL32=1 ;;
        "") echo "delete-src 需要指定 --arch aarch64|armv7-a 或使用 --all"; exit 1 ;;
        *) echo "未知架构：$ARCH"; exit 1 ;;
      esac
    fi
    delete_in_root_with_layout "$SRC_ROOT" "$DEL64" "$DEL32"
    ;;

  copy-gerrit)
    [ $# -ge 2 ] || { usage; exit 1; }
    SRC_ROOT="$1"; GPU_LIB_DIR="$2"; shift 2 || true
    parse_common_flags "$@"
    if [ -z "${ARCH:-}" ]; then
      echo "copy-gerrit 需要 --arch aarch64|armv7-a"
      exit 1
    fi
    flatten_copy_to_gerrit "$SRC_ROOT" "$GPU_LIB_DIR" "$ARCH"
    ;;

  delete-gerrit)
    [ $# -ge 1 ] || { usage; exit 1; }
    GPU_LIB_DIR="$1"; shift || true
    parse_common_flags "$@"
    if [ -z "${ARCH:-}" ]; then
      echo "delete-gerrit 需要 --arch aarch64|armv7-a"
      exit 1
    fi
    flatten_delete_in_gerrit "$GPU_LIB_DIR" "$ARCH"
    ;;

  times-gerrit)
    [ $# -ge 1 ] || { usage; exit 1; }
    GPU_LIB_DIR="$1"; shift || true
    parse_common_flags "$@"
    if [ "$DEL_ALL" -eq 1 ]; then
      print_times_in_gerrit "$GPU_LIB_DIR" aarch64
      print_times_in_gerrit "$GPU_LIB_DIR" armv7-a
    else
      case "${ARCH:-}" in
        aarch64|armv7-a) print_times_in_gerrit "$GPU_LIB_DIR" "$ARCH" ;;
        "") echo "times-gerrit 需要指定 --arch aarch64|armv7-a，或使用 --all"; exit 1 ;;
        *) echo "未知架构：$ARCH"; exit 1 ;;
      esac
    fi
    ;;

  *)
    usage; exit 1 ;;
esac

