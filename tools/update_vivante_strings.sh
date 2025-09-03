#!/bin/bash
# 用法: ./replace_vivante_year.sh <目录路径>
# 例如: ./replace_vivante_year.sh /home/user/project

if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

TARGET_DIR="$1"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: $TARGET_DIR is not a directory."
    exit 1
fi

echo "正在替换目录: $TARGET_DIR 下的 '- 2024 Vivante Corporation' 为 '- 2025 Vivante Corporation'..."

# 查找所有普通文件并替换内容
find "$TARGET_DIR" -type f -exec sed -i \
    's/- 2024 Vivante Corporation/- 2025 Vivante Corporation/g' {} +

echo "替换完成！"

