#!/bin/bash
set -e

# Source Intel oneAPI environment
# Adjust path as needed for your installation
if [ -z "$ONEAPI_ROOT" ]; then
    ONEAPI_ROOT=/opt/intel/oneapi
fi

if [ -f "$ONEAPI_ROOT/setvars.sh" ]; then
    source "$ONEAPI_ROOT/setvars.sh"
else
    echo "Error: Intel oneAPI not found at $ONEAPI_ROOT"
    echo "Set ONEAPI_ROOT environment variable to your Intel oneAPI installation path"
    exit 1
fi

# Build
BUILD_DIR=build-intel
mkdir -p $BUILD_DIR
cd $BUILD_DIR

cmake .. \
    -DCMAKE_CXX_COMPILER=icpx \
    -DCMAKE_BUILD_TYPE=Release

cmake --build . -j$(nproc)

echo ""
echo "Build complete. Run with: ./$BUILD_DIR/sycl_jit_example"
