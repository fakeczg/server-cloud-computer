#!/bin/bash
#
# usage:
#   ./mount_android_parts.sh b    # 挂载 /dev/sdb1..4
#   ./mount_android_parts.sh -u   # 卸载 /mnt/boot..data
#

set -e

MNT_BASE="/mnt"
PARTS=(boot system vendor data)

mount_partitions() {
	local disk_letter=$1
	for i in "${!PARTS[@]}"; do
		part_num=$((i + 1))
		dev="/dev/sd${disk_letter}${part_num}"
		dir="${MNT_BASE}/${PARTS[$i]}"

		# 确保目录存在
		[ -d "$dir" ] || sudo mkdir -p "$dir"

		echo "[INFO] 挂载 $dev -> $dir"
		sudo mount "$dev" "$dir"
	done
}

umount_partitions() {
	for dir in "${PARTS[@]}"; do
		mnt="${MNT_BASE}/${dir}"
		if mountpoint -q "$mnt"; then
			echo "[INFO] 卸载 $mnt"
			sudo umount "$mnt"
		else
			echo "[SKIP] $mnt 未挂载"
		fi
	done
}

# 主逻辑
if [ $# -lt 1 ]; then
	echo "用法: $0 <磁盘字母>   # 挂载 /dev/sdX[1-4]"
	echo "     $0 -u           # 卸载 /mnt/boot /mnt/system /mnt/vendor /mnt/data"
	exit 1
fi

if [ "$1" == "-u" ]; then
	umount_partitions
else
	mount_partitions "$1"
fi
