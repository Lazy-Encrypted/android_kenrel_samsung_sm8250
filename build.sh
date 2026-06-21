#!/bin/bash
# build.sh - Kernel build script for android_kernel_samsung_sm8250 (r8q / S20 FE)
# Adapted for CI usage (GitHub Actions) with AOSP Clang
set -e

# ----------------------------------------------------------------------------
# Fixed target properties (S20 FE, Qualcomm SM8250)
# ----------------------------------------------------------------------------
MODEL="${MODEL:-r8q}"
REGION="${REGION:-}"
CHIPSET_NAME="kona"
KERNEL_ARCH="arm64"
PERMISSIVE="${PERMISSIVE:-false}"
INCLUDE_KSU="${INCLUDE_KSU:-false}"

export PROJECT_NAME="${MODEL}"
[ -z "${PLATFORM_VERSION}" ] && export PLATFORM_VERSION=11

# ----------------------------------------------------------------------------
# Submodules (only relevant if this tree actually uses git submodules;
# ata-kaner/pascua28 tree ships techpack/etc as regular tracked folders)
# ----------------------------------------------------------------------------
if [ -f .gitmodules ] && [ -s .gitmodules ]; then
    UNINITIALIZED_SUBMODULES=$(git submodule status | grep '^-' || true)
    if [ -n "$UNINITIALIZED_SUBMODULES" ]; then
        echo "Initializing and cloning submodules..."
        git submodule update --init --recursive
    else
        echo "All submodules are already initialized."
    fi
else
    echo "No submodules found in this repository."
fi

# ----------------------------------------------------------------------------
# Build paths
# ----------------------------------------------------------------------------
PRODUCT_OUT=out
KERNEL_DIR=$(pwd)
KERNEL_OUT_DIR="$PRODUCT_OUT/obj/KERNEL_OBJ"

mkdir -p "$KERNEL_OUT_DIR"

# ----------------------------------------------------------------------------
# Defconfigs
# ----------------------------------------------------------------------------
KERNEL_DEFCONFIG="vendor/${CHIPSET_NAME}-perf_defconfig"
COMMON_DEFCONFIG="vendor/samsung/kona-sec-common.config"

if [ -n "$REGION" ]; then
    PROJECT_CONFIG="vendor/samsung/${MODEL}_${REGION}.config"
else
    PROJECT_CONFIG="vendor/samsung/${MODEL}.config"
fi

if [ "$PERMISSIVE" = true ]; then
    SLNX_DEFCONFIG="vendor/permissive.config"
fi

if [ "$INCLUDE_KSU" = true ] && [ -n "$KSU_DEFCONFIG" ]; then
    echo "Using KernelSU defconfig fragment: $KSU_DEFCONFIG"
fi

# ----------------------------------------------------------------------------
# Toolchain setup (AOSP Clang, expected to be unpacked at $TOOLCHAIN_DIR)
# ----------------------------------------------------------------------------
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$KERNEL_DIR/../toolchain/clang/bin}"

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Error: AOSP Clang toolchain not found at $TOOLCHAIN_DIR. Exiting."
    exit 1
fi

PATH="$TOOLCHAIN_DIR:${PATH}"
export PATH

export CC="ccache clang"
export LLVM=1
export LLVM_IAS=1
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export READELF=llvm-readelf
export STRIP=llvm-strip
export LD=ld.lld
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export DTC_OVERLAY_TEST_EXT="$KERNEL_DIR/tools/ufdt_apply_overlay"

BUILD_JOB_NUMBER=$(nproc --all)

# ----------------------------------------------------------------------------
# Build kernel
# ----------------------------------------------------------------------------
FUNC_BUILD_KERNEL() {
    local __dts_dir="${KERNEL_OUT_DIR}/arch/${KERNEL_ARCH}/boot/dts"

    echo "=============================================="
    echo "Build Info"
    echo "Project: $PROJECT_NAME"
    echo "Common config: $KERNEL_DEFCONFIG"
    echo "Project config: $PROJECT_CONFIG"
    echo "Extra included configs: $KSU_DEFCONFIG $SLNX_DEFCONFIG"
    echo "Output directory: $PRODUCT_OUT"
    echo "=============================================="

    make -C "$KERNEL_DIR" O="$KERNEL_OUT_DIR" ARCH="$KERNEL_ARCH" \
        $KERNEL_DEFCONFIG \
        $COMMON_DEFCONFIG \
        $PROJECT_CONFIG \
        $KSU_DEFCONFIG \
        $SLNX_DEFCONFIG

    make -C "$KERNEL_DIR" O="$KERNEL_OUT_DIR" -j"$BUILD_JOB_NUMBER" ARCH="$KERNEL_ARCH"

    cat "$__dts_dir/vendor/qcom"/*.dtb > "$PRODUCT_OUT/dtb.img"

    cp "$KERNEL_OUT_DIR/arch/arm64/boot/dtbo.img" "$PRODUCT_OUT/dtbo.img"
    rsync -cv "$KERNEL_OUT_DIR/arch/arm64/boot/Image" "$PRODUCT_OUT/Image"

    ls -al "$PRODUCT_OUT/Image" "$PRODUCT_OUT/dtb.img" "$PRODUCT_OUT/dtbo.img"
}

FUNC_BUILD_KERNEL

echo ""
echo "=============================================="
echo "Build finished. Artifacts in $PRODUCT_OUT/"
echo "=============================================="
