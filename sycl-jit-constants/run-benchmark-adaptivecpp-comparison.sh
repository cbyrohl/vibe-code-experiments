#!/bin/bash
set -e

# Runs both JIT (generic) and AOT (omp) benchmarks and compares results
# This demonstrates that specialization constants ONLY work with JIT compilation

echo "================================================================"
echo "AdaptiveCpp: JIT vs AOT Compilation Comparison"
echo "================================================================"
echo ""
echo "This script compares:"
echo "  JIT Mode:  --acpp-targets=generic (runtime JIT)"
echo "  AOT Mode:  --acpp-targets=omp (OpenMP CPU, no JIT)"
echo ""
echo "Expected results:"
echo "  JIT:  High speedup (>5x) - specialization constants work"
echo "  AOT:  Low speedup (<2x)  - specialization constants don't work"
echo ""
echo "================================================================"
echo ""

# Run JIT benchmark
echo "Running JIT mode benchmark (generic)..."
echo ""
./run-benchmark-adaptivecpp-jit.sh
JIT_EXIT_CODE=$?

echo ""
echo ""

# Run AOT benchmark
echo "Running AOT mode benchmark (omp)..."
echo ""
./run-benchmark-adaptivecpp-aot.sh
AOT_EXIT_CODE=$?

echo ""
echo "================================================================"
echo "Comparison Summary"
echo "================================================================"
echo ""

# Extract speedup values from the build directories
JIT_SPEEDUP=$(grep "Actual speedup:" build-benchmark-adaptivecpp-jit/benchmark_results_jit_*.txt 2>/dev/null | tail -1 | awk '{print $3}' || echo "N/A")
AOT_SPEEDUP=$(grep "Actual speedup:" build-benchmark-adaptivecpp-aot/benchmark_results_aot_*.txt 2>/dev/null | tail -1 | awk '{print $3}' || echo "N/A")

echo "JIT Mode (generic):"
echo "  Speedup: $JIT_SPEEDUP"
echo "  Exit code: $JIT_EXIT_CODE (0=pass, 1=fail)"
echo ""

echo "AOT Mode (omp):"
echo "  Speedup: $AOT_SPEEDUP"
echo "  Exit code: $AOT_EXIT_CODE (always 0, failure expected)"
echo ""

echo "================================================================"
echo "Conclusion"
echo "================================================================"
echo ""

if [ "$JIT_EXIT_CODE" -eq 0 ]; then
    echo "✓ JIT mode PASSED - Specialization constants work with JIT!"
else
    echo "✗ JIT mode FAILED - Specialization constants not working with JIT"
fi

echo ""
echo "AOT mode result: $AOT_SPEEDUP"
echo "  (Low speedup <5x is EXPECTED and CORRECT for AOT)"
echo ""

if [ "$JIT_EXIT_CODE" -eq 0 ]; then
    echo "================================================================"
    echo "SUCCESS: Specialization constants confirmed to work via JIT"
    echo "================================================================"
    exit 0
else
    echo "================================================================"
    echo "FAILURE: Specialization constants not working as expected"
    echo "================================================================"
    exit 1
fi
