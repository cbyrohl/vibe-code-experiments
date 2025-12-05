#!/bin/bash
set -e

# Ensure AdaptiveCpp is in PATH
if ! command -v acpp &> /dev/null; then
    echo "Error: acpp compiler not found in PATH"
    echo "Please install AdaptiveCpp or add it to PATH"
    exit 1
fi

# Build
BUILD_DIR=build-adaptivecpp
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Example: Build for OMP backend (CPU)
# For GPU, adjust --acpp-targets accordingly:
#   NVIDIA: --acpp-targets="cuda:sm_75"
#   AMD: --acpp-targets="hip:gfx906"
cmake .. \
    -DCMAKE_CXX_COMPILER=acpp \
    -DCMAKE_BUILD_TYPE=Release \
    -DACPP_TARGETS="omp"

cmake --build . -j$(nproc)

echo ""
echo "Build complete. Run with: ./$BUILD_DIR/sycl_jit_example"
