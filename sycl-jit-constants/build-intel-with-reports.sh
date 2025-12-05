#!/bin/bash
set -e

# Source Intel oneAPI environment
if [ -z "$ONEAPI_ROOT" ]; then
    ONEAPI_ROOT=/opt/intel/oneapi
fi

if [ -f "$ONEAPI_ROOT/setvars.sh" ]; then
    source "$ONEAPI_ROOT/setvars.sh"
else
    echo "Error: Intel oneAPI not found at $ONEAPI_ROOT"
    exit 1
fi

# Build with optimization reports
BUILD_DIR=build-intel-reports
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Additional flags for optimization analysis:
# -fsycl-device-code-split=per_kernel : Generate separate object files per kernel
# -Rpass=inline : Report inlining decisions
# -Rpass-analysis=loop-vectorize : Report vectorization analysis
# -fsave-optimization-record : Save optimization records to YAML
# -gline-tables-only : Minimal debug info for better profiling
EXTRA_FLAGS="-fsycl-device-code-split=per_kernel -Rpass=inline -Rpass-analysis=loop-vectorize -gline-tables-only"

cmake .. \
    -DCMAKE_CXX_COMPILER=icpx \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="$EXTRA_FLAGS"

echo ""
echo "Building with optimization reports enabled..."
echo "=============================================="
cmake --build . -j$(nproc) 2>&1 | tee optimization_report.txt

echo ""
echo "=============================================="
echo "Build complete. Optimization report saved to:"
echo "  $BUILD_DIR/optimization_report.txt"
echo ""
echo "To inspect SPIR-V/assembly:"
echo "  icpx -fsycl -fsycl-device-code-split=per_kernel -save-temps ..."
echo ""
echo "Run validation tests:"
echo "  ./$BUILD_DIR/sycl_jit_example"
echo "  ./$BUILD_DIR/validation_test"
