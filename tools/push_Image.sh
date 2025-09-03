#!/bin/bash

# 检查传入的参数
if [ $# -lt 2 ]; then
	echo "Usage: $0 <path_to_Image> <new_image_name>"
	exit 1
fi

# 获取传入的 Image 路径和新文件名
IMAGE_PATH="$1"
NEW_IMAGE_NAME="$2"

# 确保传入的路径存在
if [ ! -f "$IMAGE_PATH" ]; then
	echo "Error: $IMAGE_PATH does not exist or is not a valid file."
	exit 1
fi

# 获取设备的 root 权限
adb root

# 挂载设备的 /dev/block/nvme0n1p1 到 /data/temp 以只读模式
echo "Mounting /dev/block/nvme0n1p1 to /data/temp as read-only..."
adb shell "mount -o rw /dev/block/nvme0n1p1 /data/temp"

# 检查 /data/temp 是否有 Image 文件
echo "Checking if Image exists in /data/temp..."
adb shell "ls /data/temp/Image" &>/dev/null

# 如果 Image 文件存在，则重命名它为传入的新文件名
if [ $? -eq 0 ]; then
	echo "Image exists. Renaming it to $NEW_IMAGE_NAME..."
	adb shell "mv /data/temp/Image /data/temp/$NEW_IMAGE_NAME"
else
	echo "No existing Image found in /data/temp."
fi

# 推送本地的 Image 文件到设备
echo "Pushing Image from $IMAGE_PATH to /data/temp/Image..."
adb push "$IMAGE_PATH" /data/temp/Image

# 验证文件是否成功上传
echo "Verifying the file exists on device..."
adb shell "ls /data/temp/Image"

if [ $? -eq 0 ]; then
	echo "Image file successfully pushed to /data/temp/Image"
else
	echo "Failed to push Image file."
	exit 1
fi
