#!/usr/bin/env bash
# 用法示例：
#   初始化配置：
#     cd ~/src/kernel/openharmony_linux_kernel_6.6
#     /home/chenzigui/server-cloud-computer/tools/make_kernel_prebuilt.sh oh ~/src/openharmony/5.1.0/src 1
#
#   增量编译（复用已有 .config）：
#     /home/chenzigui/server-cloud-computer/tools/make_kernel_prebuilt.sh oh ~/src/openharmony/5.1.0/src 0
#
#   Android 同理：
#     ... make_kernel_prebuilt.sh an ~/src/Android/AN13/src/aosp 1/0
#
#   第四参数 mrproper 模式（不编译）：
#     make_kernel_prebuilt.sh oh ~/src/openharmony/5.1.0/src 0 mrproper

set -euo pipefail

usage() {
    echo "用法: $0 {oh|an} <project_root> {0|1} [mrproper]"
    echo "  oh: OpenHarmony 工程根路径 (PROJ_ROOT)"
    echo "  an: Android AOSP 工程根路径 (AOSP_HOME)"
    echo "  第三个参数:"
    echo "    1 = defconfig + menuconfig"
    echo "    0 = 直接构建 (需已有 .config)"
    echo "  第四参数可选:"
    echo "    mrproper = 清理构建环境，不执行编译"
    exit 1
}

# 参数检查
if [ "$#" -lt 3 ]; then
    echo "ERROR: 参数数量不足"
    usage
fi

MODE="$1"
ROOT="$2"
CONFIG_MODE="$3"

# 检查 mrproper 开关
MRP="0"
if [[ "${4:-}" == "mrproper" ]]; then
    MRP="1"
fi

if [[ "$CONFIG_MODE" != "0" && "$CONFIG_MODE" != "1" ]]; then
    echo "ERROR: 第三个参数必须是 0 或 1"
    usage
fi

if [ ! -d "$ROOT" ]; then
    echo "ERROR: 路径不存在: $ROOT"
    exit 1
fi

KERNEL_DIR="$PWD"
if [ ! -f "$KERNEL_DIR/Makefile" ]; then
    echo "ERROR: 当前目录不是内核源码根目录（缺少 Makefile）:"
    echo "  当前目录: $KERNEL_DIR"
    exit 1
fi

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CC=clang
export HOSTCC=clang
export LLVM=1
export LLVM_IAS=1

DEFCONFIG=""

case "$MODE" in
    oh)
        export PROJ_ROOT="$ROOT"
        export PATH="$PROJ_ROOT/prebuilts/clang/ohos/linux-x86_64/llvm/bin:$PROJ_ROOT/prebuilts/gcc/linux-x86/aarch64/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin:$PATH"
        DEFCONFIG="phytium_standard_defconfig"

        echo "[OH] OpenHarmony 环境："
        echo "  PROJ_ROOT = $PROJ_ROOT"
        ;;
    an)
        export AOSP_HOME="$ROOT"
        export PATH="$AOSP_HOME/prebuilts/clang/host/linux-x86/clang-r450784d/bin:$PATH"
        DEFCONFIG="phytium_gki_defconfig"

        echo "[AN] Android 环境："
        echo "  AOSP_HOME = $AOSP_HOME"
        ;;
    *)
        echo "ERROR: 第一个参数必须是 oh 或 an。"
        usage
        ;;
esac

echo "  KERNEL_DIR = $KERNEL_DIR"
echo "  使用 defconfig = $DEFCONFIG"
echo "  CONFIG_MODE = $CONFIG_MODE (1=defconfig+menuconfig, 0=直接构建)"
echo "  MRP_MODE    = $MRP  (1=mrproper, 0=正常编译)"
echo
echo "开始..."

cd "$KERNEL_DIR"

# =========================
#  mrproper 模式处理逻辑
# =========================
if [[ "$MRP" == "1" ]]; then
    echo
    echo ">>> make mrproper  (跳过编译)"
    make mrproper
    echo
    echo "mrproper 清理完成"
    exit 0
fi

# =========================
#  正常构建模式
# =========================
if [[ "$CONFIG_MODE" == "1" ]]; then
    echo
    echo ">>> make $DEFCONFIG"
    make "$DEFCONFIG"

    echo
    echo ">>> make menuconfig"
    make menuconfig
else
    if [ -f ".config" ]; then
        echo
        echo "检测到 .config，跳过 defconfig/menuconfig，直接构建。"
    else
        echo
        echo "ERROR: 未找到 .config：$KERNEL_DIR/.config"
        echo "  需先 CONFIG_MODE=1 运行一次"
        exit 1
    fi
fi

echo
#echo ">>> make -j32"
echo ">>> bear -- make -j32"
bear -- make -j32

echo
echo "内核编译完成。"

