#!/usr/bin/env bash
# push_image_no_backup.sh
# 用法：
#   ./push_image_no_backup.sh <path_to_local_Image>

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path_to_local_Image>"
  exit 1
fi

# ---------- 可按需改动的常量 ----------
LOCAL_IMAGE="$1"
BLOCK_DEV="/dev/block/nvme0n1p1"
MNT_POINT="/data/temp"
REMOTE_IMAGE="${MNT_POINT}/Image"
# -------------------------------------

if [[ ! -f "$LOCAL_IMAGE" ]]; then
  echo "Error: $LOCAL_IMAGE does not exist or is not a regular file."
  exit 1
fi

echo "[1/8] adb root & wait-for-device"
adb root >/dev/null 2>&1 || true
adb wait-for-device

echo "[2/8] 准备挂载点 ${MNT_POINT}"
adb shell "mkdir -p ${MNT_POINT}"

echo "[3/8] 挂载 ${BLOCK_DEV} 到 ${MNT_POINT}（rw）"
adb shell "mount | grep -q ' ${MNT_POINT} '" || adb shell "mount -o rw ${BLOCK_DEV} ${MNT_POINT}"

# 记录旧文件信息（如果存在）
echo "[4/8] 检查是否存在旧的 Image"
if adb shell "[ -e '${REMOTE_IMAGE}' ]"; then
  echo "    发现旧文件，收集信息："
  adb shell "stat -c 'OLD -> size:%s bytes  mtime:%y  inode:%i' '${REMOTE_IMAGE}'" || true

  echo "    删除旧文件..."
  adb shell "rm -f '${REMOTE_IMAGE}'"

  # 确认已删除
  if adb shell "[ -e '${REMOTE_IMAGE}' ]"; then
    echo "Error: 旧文件删除失败：${REMOTE_IMAGE}"
    exit 1
  else
    echo "    旧文件已删除 ✅"
  fi
else
  echo "    未发现旧文件，跳过删除。"
fi

# 推送新文件前，打印本地信息
LOCAL_SIZE=$(stat -c '%s' "$LOCAL_IMAGE")
LOCAL_TIME=$(stat -c '%y' "$LOCAL_IMAGE")
LOCAL_SHA1=$(sha1sum "$LOCAL_IMAGE" | awk '{print $1}')
echo "[5/8] 本地文件：size:${LOCAL_SIZE} bytes  mtime:${LOCAL_TIME}  sha1:${LOCAL_SHA1}"

echo "[6/8] 推送新 Image 到设备：${REMOTE_IMAGE}"
adb push "$LOCAL_IMAGE" "$REMOTE_IMAGE" >/dev/null

# 确认新文件存在
if ! adb shell "[ -e '${REMOTE_IMAGE}' ]"; then
  echo "Error: 推送失败，设备上未发现 ${REMOTE_IMAGE}"
  exit 1
fi

# 对比大小/时间戳与哈希
echo "[7/8] 读取设备端文件信息"
adb shell "stat -c 'NEW -> size:%s bytes  mtime:%y  inode:%i' '${REMOTE_IMAGE}'" || true
REMOTE_SIZE=$(adb shell "stat -c '%s' '${REMOTE_IMAGE}'" | tr -d '\r')
REMOTE_SHA1=$(adb shell "sha1sum '${REMOTE_IMAGE}' | awk '{print \$1}'" | tr -d '\r')

echo "[8/8] 校验结果"
echo "    local_size=$LOCAL_SIZE   remote_size=$REMOTE_SIZE"
echo "    local_sha1=$LOCAL_SHA1   remote_sha1=$REMOTE_SHA1"

if [[ "$LOCAL_SIZE" != "$REMOTE_SIZE" ]]; then
  echo "Error: 大小不一致！"
  exit 1
fi
if [[ "$LOCAL_SHA1" != "$REMOTE_SHA1" ]]; then
  echo "Error: sha1 不一致！"
  exit 1
fi

echo "✅ 替换完成并通过校验。"
echo "   路径：${REMOTE_IMAGE}"
adb shell "sync"
