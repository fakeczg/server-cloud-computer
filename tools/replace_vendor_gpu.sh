#!/bin/bash

TARGET_DIR="/home/chenzigui/src/Android/AN13/src/kernel/android_common_kernel_6.6/drivers/gpu/drm/phytium/FTG340"

# 行内替换规则
REPLACEMENTS=(
  "Copyright (c) 2014 - 2025 Vivante Corporation===Copyright (c) 2025, Phytium Technology Co., Ltd."
  "Copyright (C) 2014 - 2025 Vivante Corporation===Copyright (c) 2025, Phytium Technology Co., Ltd."
  "Copyright (C) 2014 - 2025 Vivante Corporation===Copyright (c) 2025, Phytium Technology Co., Ltd."
  "galcore===ftg340"
  "Galcore===ftg340"
  "GALCORE===FTG340"
  "VIVANTE_PROFILER===PHYTIUM_PROFILER"
)

# 多行注释头关键词（用于快速检测）
MULTILINE_MATCH_STRING="Copyright (c) 2005 - 2025 by Vivante Corp."

# 多行注释替换，交由 Python 处理
PYTHON_REPLACER=$(cat << 'EOF'
import sys

old_block = '''/****************************************************************************
*
*    Copyright (c) 2005 - 2025 by Vivante Corp.  All rights reserved.
*
*    The material in this file is confidential and contains trade secrets
*    of Vivante Corporation. This is proprietary information owned by
*    Vivante Corporation. No part of this work may be disclosed,
*    reproduced, copied, transmitted, or used in any way for any purpose,
*    without the express written permission of Vivante Corporation.
*
*****************************************************************************/'''

new_block = '''/****************************************************************************
*
* Copyright (c) 2025 Phytium Technology Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*
*****************************************************************************/'''

path = sys.argv[1]

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"✅ 块替换: {path}")
EOF
)

# 写入临时 Python 替换器
PYTHON_FILE="/tmp/py_replacer.py"
echo "$PYTHON_REPLACER" > "$PYTHON_FILE"

echo "📂 扫描目录: $TARGET_DIR"

find "$TARGET_DIR" -type f | while read -r file; do
  MODIFIED=0

  # 检查每一条行内替换
  for rule in "${REPLACEMENTS[@]}"; do
    OLD="${rule%%===*}"
    NEW="${rule##*===}"
    if grep -qF "$OLD" "$file"; then
      sed -i "s|$OLD|$NEW|g" "$file"
      MODIFIED=1
    fi
  done

  # 如果包含版权多行头，调用 Python 替换器
  if grep -qF "$MULTILINE_MATCH_STRING" "$file"; then
    python3 "$PYTHON_FILE" "$file"
    MODIFIED=1
  fi

  [[ "$MODIFIED" -eq 1 ]] && echo "✔️ 处理完成: $file"
done

echo "🎯 所有替换完成。无备份，测试模式。"
