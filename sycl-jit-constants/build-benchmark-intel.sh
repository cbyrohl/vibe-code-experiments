#!/bin/bash
set -e

# Build and run the branch elimination performance benchmark with Intel oneAPI

# Source Intel oneAPI environment
if [ -z "$ONEAPI_ROOT" ]; then
    ONEAPI_ROOT=/opt/intel/oneapi
fi

if [ -f "$ONEAPI_ROOT/setvars.sh" ]; then
    echo "Sourcing Intel oneAPI environment..."
    source "$ONEAPI_ROOT/setvars.sh" > /dev/null 2>&1
else
    echo "Error: Intel oneAPI not found at $ONEAPI_ROOT"
    exit 1
fi

BUILD_DIR=build-benchmark-intel
mkdir -p $BUILD_DIR
cd $BUILD_DIR

echo ""
echo "============================================"
echo "Building Branch Elimination Benchmark"
echo "============================================"
echo ""

# Build with optimizations enabled
icpx -std=c++20 -fsycl -O3 -I../include \
    ../src/benchmark_branch_elimination.cpp \
    -o benchmark_branch_elimination

echo "✓ Build complete"
echo ""
echo "============================================"
echo "Running Benchmark"
echo "============================================"
echo ""

./benchmark_branch_elimination

echo ""
echo "============================================"
echo "Benchmark Complete"
echo "============================================"
