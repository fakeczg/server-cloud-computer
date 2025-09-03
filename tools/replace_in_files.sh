#!/bin/bash

# 用法提示
if [ $# -ne 3 ]; then
    echo "用法: $0 <目录> <src字符串> <dst字符串>"
    exit 1
fi

TARGET_DIR="$1"
SRC_STR="$2"
DST_STR="$3"

# 确保目录存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误：目录 $TARGET_DIR 不存在"
    exit 1
fi

# 遍历所有文件进行替换（跳过二进制文件）
find "$TARGET_DIR" -type f | while read -r file; do
    if file "$file" | grep -q text; then
        echo "替换文件: $file"
        sed -i "s/${SRC_STR}/${DST_STR}/g" "$file"
    else
        echo "跳过二进制文件: $file"
    fi
done

echo "✅ 所有文本文件替换完成。"

