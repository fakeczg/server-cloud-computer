#!/usr/bin/env bash
# Script Name: Universal Android/OpenHarmony Image Flasher (Safe Edition)
# Version: 6.3
# Author: AI Assistant

set -euo pipefail
IFS=$'\n\t'
[[ "${FLASH_DEBUG:-0}" = "1" ]] && set -x

# ---------------- Global Config ----------------
PREFERRED_LOG="/data/var/log/storage_flash.log"
LOG_FILE="$PREFERRED_LOG"

LABEL_BOOT="BOOT"
LABEL_SYSTEM="SYSTEM"
LABEL_VENDOR="VENDOR"
LABEL_DATA="DATA"

# mkfs 选项
MKFS_FAT_OPTS=( -F32 )
MKFS_EXT4_OPTS=( -F )

# dd 参数（稳妥版）
DD_BS="1M"                 # 1MiB 兼容性更好
DD_STATUS="status=progress"
DD_IFLAG="fullblock"       # 防短读
DD_CONV="fsync"            # 写完强制刷盘

# FAT 挂载选项
MOUNT_OPTIONS_FAT="rw,umask=000,dmask=000,fmask=000,uid=0,gid=0"

# 动态检测 FAT 工具
MKFS_FAT_BIN=""

# 缓存与挂载清理
KEEP_CACHE=0
CACHE_DIR=""
TMP_MOUNT=""

# ---------------- Logging helpers ----------------
init_log() {
  local logdir
  logdir="$(dirname "$LOG_FILE")"
  if ! mkdir -p "$logdir" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/storage_flash.log"
    mkdir -p /tmp >/dev/null 2>&1 || true
    touch "$LOG_FILE" >/dev/null 2>&1 || true
  fi
}
ts() { date '+%F %T'; }
log() { echo "[$(ts)] [$1] ${*:2}" | tee -a "$LOG_FILE" ; }

banner() {
  local msg="$*"
  log INFO "────────────────────────────────────────────────────────────────"
  log INFO "▶ $msg"
  log INFO "────────────────────────────────────────────────────────────────"
}

run_cmd() {
  # run_cmd <description> -- <actual command...>
  local desc="$1"; shift
  [[ "${1:-}" == "--" ]] && shift || true
  local cmd_str; cmd_str=$(printf '%q ' "$@")
  log CMD "$desc: $cmd_str"
  "$@" > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
}

_ts() { date +%s; }
with_duration() {
  local desc="$1"; shift
  [[ "${1:-}" == "--" ]] && shift || true
  local start=$(_ts)
  banner "$desc（开始）"
  run_cmd "$desc" -- "$@"
  local end=$(_ts)
  log INFO "✅ $desc（完成，用时 $((end-start)) 秒）"
}

# ---- robust error & exit cleanup ----
on_err() {
  local ec=$?; local cmd="${BASH_COMMAND:-?}"
  log ERROR "执行失败 (exit=$ec), cmd: $cmd, at ${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?}"
  exit "$ec"
}
on_exit() {
  local ec=$?
  if [[ -n "${TMP_MOUNT:-}" ]]; then
    if findmnt -n "$TMP_MOUNT" >/dev/null 2>&1; then
      log INFO "清理：卸载挂载点 $TMP_MOUNT"
      umount -f "$TMP_MOUNT" >/dev/null 2>&1 || true
    fi
    rmdir "$TMP_MOUNT" >/dev/null 2>&1 || true
  fi
  if (( KEEP_CACHE == 0 )) && [[ -n "${CACHE_DIR:-}" ]] && [[ "$CACHE_DIR" == /tmp/flash-cache-* ]]; then
    log INFO "清理：删除临时缓存 $CACHE_DIR"
    rm -rf "$CACHE_DIR" >/dev/null 2>&1 || true
  fi
  sync || true
  exit "$ec"
}
trap on_err ERR
trap on_exit EXIT

# ---------------- Early diagnostics ----------------
script_realpath() { readlink -f "$0" 2>/dev/null || printf '%s\n' "$0"; }
detect_crlf() {
  local me; me="$(script_realpath)"
  if grep -q $'\r' "$me" 2>/dev/null; then
    log WARN "脚本含 Windows(CRLF) 换行，建议执行：dos2unix $me"
  fi
}
detect_noexec_mount() {
  local me dir mnt opts
  me="$(script_realpath)"; dir="$(dirname "$me")"
  mnt="$(df -P "$dir" | tail -1 | awk '{print $6}')"
  opts="$(awk -v m="$mnt" '($2==m){print $4}' /proc/mounts | head -n1)"
  if [[ "${opts:-}" == *"noexec"* ]]; then
    log WARN "当前挂载点含 noexec: $mnt"
    log WARN "建议：sudo bash $me …  或将脚本移至可执行分区（如 /home）"
  fi
}

# ---------------- Help ----------------
show_help() {
  cat <<'EOF'
用法:
  # 纯格式化（仅格式化，不写镜像）
  sudo bash /绝对路径/flash_oh_an.sh --format=all|1[,2[,3[,4]]] <disk_letter>

  # 烧录模式（默认不格式化；需显式传 --format 才会格式化）
  sudo bash /绝对路径/flash_oh_an.sh <MODE> <SRC_DIR> <disk_letter> [--format=all|1[,2[,3[,4]]]] [--keep-cache]

参数:
  MODE         an = Android；oh = OpenHarmony
  SRC_DIR      必须包含 ramdisk.img / system.img / vendor.img
  disk_letter  目标盘符字母 b-z（/dev/sda 永远禁止）
  --format     可选；默认不格式化。支持 all 或 1,2,3,4 任意组合（逗号分隔）
               1 → /dev/sdX1 (FAT32)；2/3/4 → /dev/sdX{2,3,4} (ext4)
  --keep-cache 可选；源目录若为 sshfs，缓存到 /tmp，默认结束后删除；加该参数则保留

输出 & 日志:
  终端与日志双写：/data/var/log/storage_flash.log（失败回落 /tmp/storage_flash.log）
  实时监控：sudo tail -f /data/var/log/storage_flash.log || sudo tail -f /tmp/storage_flash.log

调试:
  sudo FLASH_DEBUG=1 bash /绝对路径/flash_oh_an.sh --format=4 b
EOF
}

# ---------------- Checks ----------------
need_cmds=(blkid lsblk mount umount findmnt mkfs.ext4 dd df stat blockdev tr)

validate_env() {
  if [[ $EUID -ne 0 ]]; then log ERROR "必须 root 运行"; exit 1; fi
  for c in "${need_cmds[@]}"; do
    command -v "$c" >/dev/null 2>&1 || { log ERROR "缺少命令: $c"; exit 1; }
  done
  if command -v mkfs.fat >/dev/null 2>&1; then
    MKFS_FAT_BIN="mkfs.fat"
  elif command -v mkfs.vfat >/dev/null 2>&1; then
    MKFS_FAT_BIN="mkfs.vfat"
  else
    log ERROR "缺少命令：mkfs.fat 或 mkfs.vfat（需安装 dosfstools）"
    exit 1
  fi
  log INFO "使用 FAT 格式化工具: $MKFS_FAT_BIN"
}

assert_safe_device() {
  local DEV="$1"
  if [[ ! -b "/dev/$DEV" ]]; then
    log ERROR "设备不存在: /dev/$DEV"
    run_cmd "当前块设备清单" -- lsblk -o NAME,SIZE,TYPE,RM,RO,MODEL,SERIAL
    exit 1
  fi
  if [[ "$DEV" == "sda" ]]; then
    log ERROR "禁止对 /dev/sda 操作！"
    exit 1
  fi
}

ensure_parts_exist() {
  local DEV="$1"; shift
  local ids=("$@") p
  for p in "${ids[@]}"; do
    [[ "$p" =~ ^[1-4]$ ]] || { log ERROR "非法分区编号: $p"; exit 1; }
    [[ -b "/dev/${DEV}${p}" ]] || { log ERROR "缺少分区设备 /dev/${DEV}${p}"; exit 1; }
  done
}

umount_if_mounted() {
  local PART="$1"
  if findmnt -n "$PART" >/dev/null 2>&1; then
    run_cmd "卸载分区 $PART" -- umount -f "$PART"
  fi
}

# ---------------- --format 解析 ----------------
declare -A FORMAT_MAP
parse_format_arg() {
  local arg="${1:-}" tok
  FORMAT_MAP=()
  [[ -z "$arg" ]] && return 0
  if [[ "$arg" == "all" ]]; then
    FORMAT_MAP["1"]=1; FORMAT_MAP["2"]=1; FORMAT_MAP["3"]=1; FORMAT_MAP["4"]=1; return 0
  fi
  IFS=',' read -r -a parts <<< "$arg"
  for tok in "${parts[@]}"; do
    tok="${tok//[[:space:]]/}"
    [[ "$tok" =~ ^[1-4]$ ]] || { log ERROR "无效的 --format 项: '$tok'（只能 1/2/3/4 或 all）"; exit 1; }
    FORMAT_MAP["$tok"]=1
  done
}

# ---------------- FS helpers ----------------
get_fstype() { blkid -o value -s TYPE "$1" 2>/dev/null || echo ""; }
is_fat_like() { [[ "${1:-}" =~ ^(vfat|fat|fat32|msdos)$ ]]; }

# ---------------- 可选格式化 ----------------
format_selected_partitions() {
  local DEV="$1"
  local ids=() k
  for k in "${!FORMAT_MAP[@]}"; do ids+=("$k"); done
  ensure_parts_exist "$DEV" "${ids[@]}"

  if [[ -n "${FORMAT_MAP[1]:-}" ]]; then
    umount_if_mounted "/dev/${DEV}1"
    with_duration "mkfs.FAT /dev/${DEV}1 (label=$LABEL_BOOT)" -- "$MKFS_FAT_BIN" "${MKFS_FAT_OPTS[@]}" -n "$LABEL_BOOT" "/dev/${DEV}1"
  fi
  if [[ -n "${FORMAT_MAP[2]:-}" ]]; then
    umount_if_mounted "/dev/${DEV}2"
    with_duration "mkfs.ext4 /dev/${DEV}2 (label=$LABEL_SYSTEM)" -- mkfs.ext4 "${MKFS_EXT4_OPTS[@]}" -L "$LABEL_SYSTEM" "/dev/${DEV}2"
  fi
  if [[ -n "${FORMAT_MAP[3]:-}" ]]; then
    umount_if_mounted "/dev/${DEV}3"
    with_duration "mkfs.ext4 /dev/${DEV}3 (label=$LABEL_VENDOR)" -- mkfs.ext4 "${MKFS_EXT4_OPTS[@]}" -L "$LABEL_VENDOR" "/dev/${DEV}3"
  fi
  if [[ -n "${FORMAT_MAP[4]:-}" ]]; then
    umount_if_mounted "/dev/${DEV}4"
    with_duration "mkfs.ext4 /dev/${DEV}4 (label=$LABEL_DATA)" -- mkfs.ext4 "${MKFS_EXT4_OPTS[@]}" -L "$LABEL_DATA" "/dev/${DEV}4"
  fi
}

# ---------------- sshfs 缓存（rsync 优先） ----------------
is_sshfs_path() {
  local p="$1" fstype
  fstype=$(df -T "$p" 2>/dev/null | awk 'NR==2{print $2}')
  [[ "${fstype:-}" == "fuse.sshfs" ]]
}

cache_source_if_needed() {
  local SRC="$1"
  if is_sshfs_path "$SRC"; then
    CACHE_DIR="$(mktemp -d /tmp/flash-cache-XXXX)"
    banner "源目录位于 sshfs：开始缓存到本地 $CACHE_DIR"
    if command -v rsync >/dev/null 2>&1; then
      with_duration "rsync ramdisk.img -> cache" -- rsync -av --progress "$SRC/ramdisk.img" "$CACHE_DIR/"
      with_duration "rsync system.img  -> cache" -- rsync -av --progress "$SRC/system.img"  "$CACHE_DIR/"
      with_duration "rsync vendor.img  -> cache" -- rsync -av --progress "$SRC/vendor.img"  "$CACHE_DIR/"
    else
      log WARN "未检测到 rsync，回退为 cp（可能较慢）。建议安装：sudo apt-get install rsync 或 sudo dnf install rsync"
      with_duration "复制 ramdisk.img -> cache" -- cp -f "$SRC/ramdisk.img" "$CACHE_DIR/"
      with_duration "复制 system.img  -> cache" -- cp -f "$SRC/system.img"  "$CACHE_DIR/"
      with_duration "复制 vendor.img  -> cache" -- cp -f "$SRC/vendor.img"  "$CACHE_DIR/"
    fi
    run_cmd "缓存文件清单" -- ls -lb --group-directories-first "$CACHE_DIR"
    log INFO "✅ 缓存完成：$CACHE_DIR"
  else
    CACHE_DIR=""
  fi
}

# ---------------- I/O ----------------
tmp_mountpoint() { mktemp -d /tmp/flash_mnt.XXXX; }

copy_ramdisk_to_fat() {
  local DEV="$1" SRC="$2"
  TMP_MOUNT="$(tmp_mountpoint)"
  banner "挂载 /dev/${DEV}1 并复制 ramdisk.img"
  with_duration "mount /dev/${DEV}1 -> $TMP_MOUNT" -- mount -o "$MOUNT_OPTIONS_FAT" "/dev/${DEV}1" "$TMP_MOUNT"

  if command -v rsync >/dev/null 2>&1; then
    with_duration "rsync ramdisk.img -> ${TMP_MOUNT}/ramdisk.img" -- \
      rsync -r --progress --whole-file --inplace \
            --no-owner --no-group --no-perms \
            "$SRC/ramdisk.img" "$TMP_MOUNT/ramdisk.img"
  else
    log WARN "未检测到 rsync，ramdisk 使用 cp 回退"
    with_duration "cp ramdisk.img -> ${TMP_MOUNT}/ramdisk.img" -- cp -f "$SRC/ramdisk.img" "$TMP_MOUNT/ramdisk.img"
  fi

  run_cmd "sync" -- sync
  with_duration "umount $TMP_MOUNT" -- umount "$TMP_MOUNT"
  rmdir "$TMP_MOUNT" || true
  TMP_MOUNT=""
  log SUCCESS "ramdisk.img 已复制到 /dev/${DEV}1"
}

check_img_fits_partition() {
  local IMG="$1" PART="$2"
  local img_bytes part_bytes
  img_bytes=$(stat -c '%s' "$IMG")
  part_bytes=$(blockdev --getsize64 "$PART")
  if (( img_bytes > part_bytes )); then
    log ERROR "镜像过大 (${img_bytes}B) > 分区容量 (${part_bytes}B): $PART"
    exit 1
  fi
}

dd_image_to_part() {
  local IMG="$1" PART="$2" tag="$3"
  [[ -f "$IMG" ]] || { log ERROR "镜像不存在: $IMG"; exit 1; }
  [[ -b "$PART" ]] || { log ERROR "目标分区不存在: $PART"; exit 1; }

  umount_if_mounted "$PART"
  check_img_fits_partition "$IMG" "$PART"

  banner "开始写入 ${tag} → ${PART}"

  # 用 iflag=fullblock + conv=fsync；不再使用 oflag=direct
  with_duration "dd $tag -> $PART" -- \
    dd if="$IMG" of="$PART" bs="$DD_BS" $DD_STATUS iflag="$DD_IFLAG" conv="$DD_CONV"

  # 进一步确保数据真正落到设备
  run_cmd "blockdev --flushbufs $PART" -- blockdev --flushbufs "$PART"
  run_cmd "udevadm settle" -- udevadm settle || true

  log SUCCESS "${tag} 写入完成"
}


verify_brief() {
  local DEV="$1"
  banner "设备摘要 / 校验"
  run_cmd "blkid /dev/${DEV}[1-4]" -- sh -c 'for p in 1 2 3 4; do [[ -b "/dev/'"$DEV"'$p" ]] && blkid "/dev/'"$DEV"'$p"; done'
  run_cmd "lsblk /dev/$DEV" -- lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "/dev/$DEV"
}

# ---------------- Main ----------------
main() {
  init_log
  log INFO "==== 脚本启动 $(script_realpath) ===="
  detect_crlf
  detect_noexec_mount

  # 无参数或 help
  if [[ $# -eq 0 ]]; then log ERROR "缺少参数。查看帮助：./flash_oh_an.sh help"; show_help; exit 1; fi
  if [[ $# -eq 1 && "$1" == "help" ]]; then show_help; exit 0; fi

  # 模式 A：纯格式化
  if [[ "$1" == --format=* ]]; then
    if [[ $# -ne 2 ]]; then log ERROR "纯格式化模式需要两个参数：--format=... <disk_letter>"; show_help; exit 1; fi
    local FORMAT_RAW="${1#--format=}"; local LETTER="$2"
    log INFO "参数解析：FORMAT_RAW='$FORMAT_RAW' LETTER='$LETTER'"
    [[ "$LETTER" =~ ^[b-zB-Z]$ ]] || { log ERROR "盘符非法：$LETTER（应为 b-z）"; show_help; exit 1; }

    validate_env
    local DEV="sd$(echo "$LETTER" | tr '[:upper:]' '[:lower:]')"
    log INFO "LETTER→DEV 映射：$LETTER → $DEV"
    assert_safe_device "$DEV"

    parse_format_arg "$FORMAT_RAW"
    (( ${#FORMAT_MAP[@]} > 0 )) || { log ERROR "--format 不能为空"; show_help; exit 1; }

    banner "进入纯格式化模式：/dev/$DEV  分区: ${!FORMAT_MAP[*]}"
    format_selected_partitions "$DEV"
    verify_brief "$DEV"
    log SUCCESS "纯格式化完成（目标: /dev/$DEV；选择: ${!FORMAT_MAP[*]}）"
    exit 0
  fi

  # 模式 B：烧录
  if (( $# < 3 )); then log ERROR "烧录模式参数数量不正确。"; show_help; exit 1; fi

  local MODE="$1" SRC_DIR="$2" LETTER="$3" FORMAT_RAW=""
  shift 3
  while (( $# > 0 )); do
    case "$1" in
      --format=*) FORMAT_RAW="${1#--format=}" ;;
      --keep-cache) KEEP_CACHE=1 ;;
      *) log ERROR "未知参数：$1"; show_help; exit 1 ;;
    esac
    shift
  done

  log INFO "参数解析：MODE='$MODE' SRC_DIR='$SRC_DIR' LETTER='$LETTER' FORMAT='${FORMAT_RAW:-<无>}' KEEP_CACHE=$KEEP_CACHE"
  [[ "$MODE" == "an" || "$MODE" == "oh" ]] || { log ERROR "MODE 必须是 an 或 oh"; show_help; exit 1; }
  [[ -d "$SRC_DIR" ]] || { log ERROR "源目录不存在: $SRC_DIR"; show_help; exit 1; }
  [[ "$LETTER" =~ ^[b-zB-Z]$ ]] || { log ERROR "盘符非法：$LETTER（应为 b-z）"; show_help; exit 1; }

  validate_env
  local DEV="sd$(echo "$LETTER" | tr '[:upper:]' '[:lower:]')"
  log INFO "LETTER→DEV 映射：$LETTER → $DEV"
  assert_safe_device "$DEV"
  ensure_parts_exist "$DEV" 1 2 3

  parse_format_arg "$FORMAT_RAW"
  if (( ${#FORMAT_MAP[@]} > 0 )); then
    banner "格式化请求：${!FORMAT_MAP[*]}"
    format_selected_partitions "$DEV"
  else
    log INFO "未指定 --format，保持现有文件系统。"
  fi

  banner "预检查镜像目录与文件"
  cache_source_if_needed "$SRC_DIR"
  local REAL_SRC
  if [[ -n "${CACHE_DIR:-}" ]]; then
    REAL_SRC="$CACHE_DIR"
  else
    REAL_SRC="$SRC_DIR"
  fi
  log INFO "使用镜像目录: $REAL_SRC"
  run_cmd "镜像目录清单（$REAL_SRC）" -- ls -lb --group-directories-first "$REAL_SRC"
  for f in ramdisk.img system.img vendor.img; do
    [[ -f "$REAL_SRC/$f" ]] || { log ERROR "缺少文件: $REAL_SRC/$f"; exit 1; }
  done
  run_cmd "镜像大小统计" -- sh -c 'printf "ramdisk=%s  system=%s  vendor=%s 字节\n" \
      "$(stat -c "%s" "'"$REAL_SRC"'/ramdisk.img")" \
      "$(stat -c "%s" "'"$REAL_SRC"'/system.img")" \
      "$(stat -c "%s" "'"$REAL_SRC"'/vendor.img")"'

  if [[ -z "${FORMAT_MAP[1]:-}" ]]; then
    local fs1; fs1="$(get_fstype "/dev/${DEV}1")"
    if ! is_fat_like "${fs1:-}"; then
      log ERROR "/dev/${DEV}1 不是 FAT (当前: '${fs1:-未知}'). 请添加 --format=1 或 --format=all 后再试。"
      exit 1
    fi
  fi

  banner "开始烧录（模式: $MODE → /dev/$DEV）"
  copy_ramdisk_to_fat "$DEV" "$REAL_SRC"
  dd_image_to_part "$REAL_SRC/system.img" "/dev/${DEV}2" "system.img"
  dd_image_to_part "$REAL_SRC/vendor.img" "/dev/${DEV}3" "vendor.img"

  verify_brief "$DEV"
  banner "烧录完成（模式: $MODE，源: $SRC_DIR → 实际: $REAL_SRC，目标: /dev/$DEV）"
  log SUCCESS "ALL DONE"
}

main "$@"

