#!/bin/bash
set -e

# Build and run the branch elimination performance benchmark with AdaptiveCpp

# Check for AdaptiveCpp
if ! command -v acpp &> /dev/null; then
    echo "Error: acpp compiler not found in PATH"
    echo "Please install AdaptiveCpp or add it to PATH"
    exit 1
fi

echo "✓ AdaptiveCpp compiler found: $(which acpp)"
ACPP_VERSION=$(acpp --version 2>&1 | head -n1 || echo "Unknown version")
echo "  Version: $ACPP_VERSION"
echo ""

# Determine backend
if [ -z "$ACPP_TARGETS" ]; then
    ACPP_TARGETS="omp"
    echo "Using default backend: $ACPP_TARGETS (CPU via OpenMP)"
else
    echo "Using configured backend: $ACPP_TARGETS"
fi
echo ""

BUILD_DIR=build-benchmark-adaptivecpp
mkdir -p $BUILD_DIR
cd $BUILD_DIR

echo ""
echo "============================================"
echo "Building Branch Elimination Benchmark"
echo "============================================"
echo ""

# Build with optimizations enabled
acpp --acpp-targets=$ACPP_TARGETS -std=c++20 -O3 -I../include \
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
