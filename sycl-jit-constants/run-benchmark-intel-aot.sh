#!/bin/bash
set -e

# Intel AOT mode benchmark - device code compiled ahead-of-time
# Specialization constants should NOT work in this mode (values unknown at compile time)

echo "=============================================="
echo "SYCL Constant Folding Benchmark Suite"
echo "Intel oneAPI - AOT Mode"
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

BUILD_DIR=build-benchmark-intel-aot
mkdir -p $BUILD_DIR
cd $BUILD_DIR

echo ""
echo "=============================================="
echo "Building Benchmark (AOT Mode)"
echo "=============================================="
echo ""
echo "Compilation mode: AOT (ahead-of-time compilation)"
echo "  -fsycl -fsycl-targets=spir64"
echo "  Device code compiled to native at build time"
echo "  NO runtime JIT compilation"
echo ""
echo "EXPECTED: Benchmark should FAIL in this mode"
echo "  Specialization constants require JIT to optimize"
echo ""

icpx -std=c++20 -fsycl -fsycl-targets=spir64 -O3 -I../include \
    ../src/benchmark_branch_elimination.cpp \
    -o benchmark_branch_elimination

echo "✓ Build complete"
echo ""

# Configuration
NUM_TRIALS=5
RESULTS_FILE="benchmark_results_aot_$(date +%Y%m%d_%H%M%S).txt"

echo "=============================================="
echo "Running Benchmark Suite"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Mode: AOT"
echo "  Number of trials: $NUM_TRIALS"
echo "  Results file: $RESULTS_FILE"
echo ""

# Header for results file
cat > $RESULTS_FILE << EOF
SYCL Constant Folding Benchmark Results (Intel AOT Mode)
=========================================================
Date: $(date)
Compiler: $(icpx --version | head -1)
Mode: AOT (ahead-of-time compilation with -fsycl-targets=spir64)

Test: Specialization Constants as Compile-Time Constants

Critical: Multiplier values are passed at RUNTIME via command-line arguments.
          The AOT compiler (icpx) does NOT know these values during compilation.
          There is NO JIT compilation at runtime.

What we're testing:
  - mult=0: If JIT treats constant as constexpr, it should fold:
            0 * expensive_computation() → 0 (eliminating the function call)
  - mult=1: Baseline (expensive_computation() MUST execute)

Expected: In AOT mode, specialization constants CANNOT enable optimization
          because values are unknown at compile time and there's no JIT.
          Speedup should be <2x (FAIL expected)

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
    sum = 0
    for (i = 1; i < ARGC; i++) {
        ratios[i] = ARGV[i]
        sum += ARGV[i]
    }
    ARGC = 1

    mean = sum / n

    sum_sq_diff = 0
    for (i = 1; i <= n; i++) {
        diff = ratios[i] - mean
        sum_sq_diff += diff * diff
    }
    stddev = sqrt(sum_sq_diff / n)

    min = ratios[1]
    max = ratios[1]
    for (i = 2; i <= n; i++) {
        if (ratios[i] < min) min = ratios[i]
        if (ratios[i] > max) max = ratios[i]
    }

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
echo "Interpretation (AOT Mode)"
echo "=============================================="
echo ""

interpretation=""
if (( $(echo "$mean_speedup > 5.0" | bc -l) )); then
    interpretation="⚠ UNEXPECTED: Mean speedup of ${mean_speedup}x in AOT mode!"
    interpretation="$interpretation\n  This is surprising - AOT compilation shouldn't enable"
    interpretation="$interpretation\n  specialization constant optimization since values are"
    interpretation="$interpretation\n  unknown at compile time."
elif (( $(echo "$mean_speedup > 2.0" | bc -l) )); then
    interpretation="⚠ MARGINAL: Mean speedup of ${mean_speedup}x."
    interpretation="$interpretation\n  Some optimization detected, possibly from general compiler opts,"
    interpretation="$interpretation\n  but not the specialization constant mechanism."
else
    interpretation="✓ EXPECTED: Mean speedup of ${mean_speedup}x (as expected for AOT)."
    interpretation="$interpretation\n  No significant constant folding detected in AOT mode."
    interpretation="$interpretation\n  This is CORRECT - specialization constants cannot work"
    interpretation="$interpretation\n  without JIT compilation when values are runtime arguments."
fi

echo -e "$interpretation"
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
echo "  Mode: AOT"
echo "  Mean speedup: ${mean_speedup}x ± ${stddev_speedup}x"
echo "  Range: ${min_speedup}x - ${max_speedup}x"
echo "  Variability: $cv"
echo ""
echo "Note: AOT mode is EXPECTED to fail (speedup < 5x)"
echo "      because specialization constants require JIT compilation"
echo ""
echo "Full results saved to: $RESULTS_FILE"
echo ""
echo "To view detailed results:"
echo "  cat $BUILD_DIR/$RESULTS_FILE"
echo ""

# Save final result to file
cat >> $RESULTS_FILE << EOF

Final Result:
-------------
Mode: AOT
Actual speedup: ${mean_speedup}x

This is AOT mode - specialization constants CANNOT work here
because values are unknown at compile time and there's no JIT.
Low speedup (<5x) is EXPECTED and CORRECT.
EOF

echo "=============================================="
echo "AOT Mode Result (Expected to be low)"
echo "=============================================="
echo ""
echo "Speedup: ${mean_speedup}x"
echo ""
if (( $(echo "$mean_speedup < 5.0" | bc -l) )); then
    echo "✓ CORRECT: AOT mode shows low speedup (as expected)"
    echo "  Specialization constants require JIT compilation"
else
    echo "⚠ UNEXPECTED: AOT mode shows high speedup"
    echo "  This shouldn't happen with runtime-provided values"
fi
echo ""

cd ..
exit 0
