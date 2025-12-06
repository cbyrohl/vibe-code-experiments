#!/bin/bash
set -e

# Comprehensive benchmark script for constant folding testing
# Tests whether JIT compiler treats specialization constants as constexpr
# by passing multiplier values at runtime (unknown to AOT compiler)
# Runs multiple trials with proper burn-in and statistical analysis

echo "=============================================="
echo "SYCL Constant Folding Benchmark Suite"
echo "=============================================="
echo ""

# Source Intel oneAPI environment (robust, with diagnostics)
if [ -z "$ONEAPI_ROOT" ]; then
    ONEAPI_ROOT=/opt/intel/oneapi
fi

if [ -f "$ONEAPI_ROOT/setvars.sh" ]; then
    echo "Sourcing Intel oneAPI environment..."
    set +e
    source "$ONEAPI_ROOT/setvars.sh"
    SRC_RC=$?
    set -e
    # oneAPI setvars.sh returns 3 if already sourced; treat as OK
    if [ $SRC_RC -ne 0 ] && [ $SRC_RC -ne 3 ]; then
        echo "Error: Failed to source $ONEAPI_ROOT/setvars.sh (exit $SRC_RC)"
        echo "Hint: Ensure oneAPI is installed and try: source $ONEAPI_ROOT/setvars.sh"
        exit 1
    fi
    if ! command -v icpx >/dev/null 2>&1; then
        echo "Error: 'icpx' not found in PATH after sourcing oneAPI environment"
        echo "Hint: Verify your oneAPI installation and environment setup"
        exit 1
    fi
    echo "✓ Intel oneAPI environment loaded ($(icpx --version | head -1))"
else
    echo "Error: Intel oneAPI not found at $ONEAPI_ROOT"
    echo "Set ONEAPI_ROOT or install Intel oneAPI Base Toolkit"
    exit 1
fi

BUILD_DIR=build-benchmark-intel
mkdir -p $BUILD_DIR
cd $BUILD_DIR

echo ""
echo "=============================================="
echo "Building Benchmark"
echo "=============================================="
echo ""

icpx -std=c++20 -fsycl -O3 -I../include \
    ../src/benchmark_branch_elimination.cpp \
    -o benchmark_branch_elimination

echo "✓ Build complete"
echo ""

# Configuration
NUM_TRIALS=5
RESULTS_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).txt"

echo "=============================================="
echo "Running Benchmark Suite"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Number of trials: $NUM_TRIALS"
echo "  Results file: $RESULTS_FILE"
echo ""

# Header for results file
cat > $RESULTS_FILE << EOF
SYCL Constant Folding Benchmark Results
========================================
Date: $(date)
Device: $(icpx --version | head -1)

Test: Specialization Constants as Compile-Time Constants

Critical: Multiplier values are passed at RUNTIME via command-line arguments.
          The AOT compiler (icpx) does NOT know these values during compilation.
          Only the device JIT compiler sees them as specialization constants.

What we're testing:
  - mult=0: If JIT treats constant as constexpr, it should fold:
            0 * expensive_computation() → 0 (eliminating the function call)
  - mult=1: Baseline (expensive_computation() MUST execute)

If specialization constants are constexpr to JIT: expect >20x speedup
If NOT constexpr to JIT: expect <2x speedup

Trial Results:
--------------
EOF

# Arrays to store results
declare -a speedups_false=()
declare -a speedups_true=()
declare -a ratios=()

# Run trials
for trial in $(seq 1 $NUM_TRIALS); do
    echo "=============================================="
    echo "Trial $trial of $NUM_TRIALS"
    echo "=============================================="
    echo ""

    # Run benchmark with multiplier=0 (test constant folding)
    echo "Running with multiplier=0..."
    output_mult0=$(./benchmark_branch_elimination 0 2>&1)
    time_mult0=$(echo "$output_mult0" | grep "Average execution time (mult=0):" | awk '{print $5}' | tr -d 'a-zA-Z=')

    echo ""
    echo "Running with multiplier=1..."
    output_mult1=$(./benchmark_branch_elimination 1 2>&1)
    time_mult1=$(echo "$output_mult1" | grep "Average execution time (mult=1):" | awk '{print $5}' | tr -d 'a-zA-Z=')

    # Calculate speedup ratio
    speedup=$(awk -v t0="$time_mult0" -v t1="$time_mult1" 'BEGIN {printf "%.2f", t1/t0}')

    # Store results
    speedups_false+=($time_mult0)
    speedups_true+=($time_mult1)
    ratios+=($speedup)

    # Display results
    echo "Results for trial $trial:"
    echo "  Time (mult=0): $time_mult0 ms"
    echo "  Time (mult=1): $time_mult1 ms"
    echo "  Speedup:       ${speedup}x"
    echo ""

    # Save to file
    cat >> $RESULTS_FILE << EOF

Trial $trial:
  Time (mult=0): $time_mult0 ms
  Time (mult=1): $time_mult1 ms
  Speedup:       ${speedup}x
EOF

    # Small delay between trials
    sleep 1
done

echo "=============================================="
echo "Statistical Analysis"
echo "=============================================="
echo ""

# Calculate statistics using awk
stats=$(awk -v n=$NUM_TRIALS 'BEGIN {
    # Read speedup ratios from command line
    sum = 0
    for (i = 1; i < ARGC; i++) {
        ratios[i] = ARGV[i]
        sum += ARGV[i]
    }
    ARGC = 1  # Prevent awk from treating args as files

    # Calculate mean
    mean = sum / n

    # Calculate standard deviation
    sum_sq_diff = 0
    for (i = 1; i <= n; i++) {
        diff = ratios[i] - mean
        sum_sq_diff += diff * diff
    }
    stddev = sqrt(sum_sq_diff / n)

    # Find min and max
    min = ratios[1]
    max = ratios[1]
    for (i = 2; i <= n; i++) {
        if (ratios[i] < min) min = ratios[i]
        if (ratios[i] > max) max = ratios[i]
    }

    # Calculate coefficient of variation (relative std dev)
    cv = (stddev / mean) * 100

    printf "Mean: %.2f\n", mean
    printf "StdDev: %.2f\n", stddev
    printf "Min: %.2f\n", min
    printf "Max: %.2f\n", max
    printf "CV: %.1f%%\n", cv
}' ${ratios[@]})

# Parse statistics
mean_speedup=$(echo "$stats" | grep "Mean:" | awk '{print $2}')
stddev_speedup=$(echo "$stats" | grep "StdDev:" | awk '{print $2}')
min_speedup=$(echo "$stats" | grep "Min:" | awk '{print $2}')
max_speedup=$(echo "$stats" | grep "Max:" | awk '{print $2}')
cv=$(echo "$stats" | grep "CV:" | awk '{print $2}' | tr -d '%')

# Display statistics
echo "Speedup Statistics (across $NUM_TRIALS trials):"
echo "  Mean:              ${mean_speedup}x"
echo "  Standard Deviation: ${stddev_speedup}x"
echo "  Min:               ${min_speedup}x"
echo "  Max:               ${max_speedup}x"
echo "  Coefficient of Variation: $cv"
echo ""

# Save statistics to file
cat >> $RESULTS_FILE << EOF

Statistical Summary:
--------------------
Number of trials: $NUM_TRIALS

Speedup Statistics:
  Mean:              ${mean_speedup}x
  Standard Deviation: ${stddev_speedup}x
  Min:               ${min_speedup}x
  Max:               ${max_speedup}x
  Coefficient of Variation: $cv

Individual Trial Data:
EOF

for i in $(seq 0 $(($NUM_TRIALS - 1))); do
    echo "  Trial $((i+1)): ${speedups_false[$i]} ms (mult=0), ${speedups_true[$i]} ms (mult=1), ${ratios[$i]}x" >> $RESULTS_FILE
done

# Interpretation
echo "=============================================="
echo "Interpretation"
echo "=============================================="
echo ""

interpretation=""
if (( $(echo "$mean_speedup > 50.0" | bc -l) )); then
    interpretation="✓✓ EXCELLENT: Mean speedup of ${mean_speedup}x!"
    interpretation="$interpretation\n  Specialization constants ARE treated as compile-time constants."
    interpretation="$interpretation\n  The JIT compiler successfully performed constant folding:"
    interpretation="$interpretation\n    0 * expensive_computation() → 0 (computation eliminated)"
elif (( $(echo "$mean_speedup > 20.0" | bc -l) )); then
    interpretation="✓ VERY GOOD: Mean speedup of ${mean_speedup}x."
    interpretation="$interpretation\n  Strong evidence of constant folding optimization."
    interpretation="$interpretation\n  Specialization constants are likely treated as constexpr."
elif (( $(echo "$mean_speedup > 5.0" | bc -l) )); then
    interpretation="⚠ GOOD: Mean speedup of ${mean_speedup}x."
    interpretation="$interpretation\n  Partial optimization detected, but not full constant folding."
    interpretation="$interpretation\n  The compiler may not be treating specialization constants as fully constexpr."
elif (( $(echo "$mean_speedup > 2.0" | bc -l) )); then
    interpretation="⚠ MARGINAL: Mean speedup of ${mean_speedup}x."
    interpretation="$interpretation\n  Limited optimization detected."
    interpretation="$interpretation\n  Specialization constants may NOT be treated as constexpr."
else
    interpretation="✗ POOR: Mean speedup of ${mean_speedup}x."
    interpretation="$interpretation\n  No significant constant folding detected!"
    interpretation="$interpretation\n  Specialization constants are NOT treated as compile-time constants."
    interpretation="$interpretation\n  The expensive computation executes even when multiplied by 0."
fi

echo -e "$interpretation"
echo ""

# Check consistency
if (( $(echo "$cv < 10.0" | bc -l) )); then
    echo "✓ Results are CONSISTENT (CV < 10%)"
    echo "  Low variability across trials indicates reliable measurements."
elif (( $(echo "$cv < 20.0" | bc -l) )); then
    echo "⚠ Results show MODERATE variability (CV = $cv)"
    echo "  Consider running more trials for better statistical confidence."
else
    echo "✗ Results show HIGH variability (CV = $cv)"
    echo "  Measurements may be affected by thermal throttling, system load,"
    echo "  or other environmental factors. Consider:"
    echo "    - Running on a quieter system"
    echo "    - Increasing warm-up time"
    echo "    - Checking for background processes"
fi

echo ""

# Save interpretation
cat >> $RESULTS_FILE << EOF

Interpretation:
---------------
$(echo -e "$interpretation")

Consistency:
  Coefficient of Variation: $cv

EOF

echo "=============================================="
echo "Results Summary"
echo "=============================================="
echo ""
echo "✓ Benchmark complete!"
echo ""
echo "Key Findings:"
echo "  Mean speedup: ${mean_speedup}x ± ${stddev_speedup}x"
echo "  Range: ${min_speedup}x - ${max_speedup}x"
echo "  Variability: $cv"
echo "  Required threshold: 5.0x (for PASS)"
echo ""
echo "Full results saved to: $RESULTS_FILE"
echo ""
echo "To view detailed results:"
echo "  cat $BUILD_DIR/$RESULTS_FILE"
echo ""

# Check if speedup meets minimum threshold
SPEEDUP_THRESHOLD=5.0

# Save final result to file
cat >> $RESULTS_FILE << EOF

Final Result:
-------------
Speedup threshold: ${SPEEDUP_THRESHOLD}x
Actual speedup:    ${mean_speedup}x
EOF

if (( $(echo "$mean_speedup < $SPEEDUP_THRESHOLD" | bc -l) )); then
    cat >> $RESULTS_FILE << EOF
Status: FAILED

Speedup below threshold indicates specialization constants are NOT
treated as compile-time constants by the JIT compiler.
EOF

    echo "=============================================="
    echo "BENCHMARK FAILED"
    echo "=============================================="
    echo ""
    echo "Speedup of ${mean_speedup}x is below threshold of ${SPEEDUP_THRESHOLD}x"
    echo ""
    echo "This indicates that specialization constants are NOT being"
    echo "treated as compile-time constants by the JIT compiler."
    echo "Constant folding optimization (0 * f() → 0) did not occur."
    echo ""
    cd ..
    exit 1
fi

cat >> $RESULTS_FILE << EOF
Status: PASSED

Speedup meets threshold. Specialization constants appear to be
treated as compile-time constants (constexpr) by the JIT compiler.
EOF

echo "=============================================="
echo "BENCHMARK PASSED"
echo "=============================================="
echo ""
echo "Speedup of ${mean_speedup}x meets minimum threshold of ${SPEEDUP_THRESHOLD}x"
echo "Specialization constants appear to be treated as constexpr."
echo ""

cd ..
exit 0
