#!/bin/bash
set -e

# Generic benchmark runner - detects available SYCL implementations and runs benchmarks

echo "=============================================="
echo "SYCL JIT Constants Validation & Benchmark Suite"
echo "=============================================="
echo ""

# Detect available SYCL implementations
HAS_INTEL=false
HAS_ADAPTIVECPP=false

if [ ! -z "$ONEAPI_ROOT" ] && [ -f "$ONEAPI_ROOT/setvars.sh" ]; then
    HAS_INTEL=true
elif [ -f "/opt/intel/oneapi/setvars.sh" ]; then
    HAS_INTEL=true
fi

if command -v acpp &> /dev/null; then
    HAS_ADAPTIVECPP=true
fi

echo "Detecting available SYCL implementations:"
if [ "$HAS_INTEL" = true ]; then
    echo "  ✓ Intel oneAPI SYCL"
else
    echo "  ✗ Intel oneAPI SYCL (not found)"
fi

if [ "$HAS_ADAPTIVECPP" = true ]; then
    echo "  ✓ AdaptiveCpp"
else
    echo "  ✗ AdaptiveCpp (not found)"
fi
echo ""

# Check if at least one implementation is available
if [ "$HAS_INTEL" = false ] && [ "$HAS_ADAPTIVECPP" = false ]; then
    echo "Error: No SYCL implementations found!"
    echo ""
    echo "Please install one of:"
    echo "  - Intel oneAPI (set ONEAPI_ROOT or install to /opt/intel/oneapi)"
    echo "  - AdaptiveCpp (ensure 'acpp' is in PATH)"
    exit 1
fi

# Determine which implementation to use
IMPL=""
if [ ! -z "$1" ]; then
    # User specified implementation via command line
    case "$1" in
        intel|oneapi)
            if [ "$HAS_INTEL" = true ]; then
                IMPL="intel"
            else
                echo "Error: Intel oneAPI not available"
                exit 1
            fi
            ;;
        adaptivecpp|acpp)
            if [ "$HAS_ADAPTIVECPP" = true ]; then
                IMPL="adaptivecpp"
            else
                echo "Error: AdaptiveCpp not available"
                exit 1
            fi
            ;;
        all)
            IMPL="all"
            ;;
        *)
            echo "Error: Unknown implementation '$1'"
            echo "Usage: $0 [intel|adaptivecpp|all]"
            exit 1
            ;;
    esac
else
    # Auto-select based on what's available
    if [ "$HAS_INTEL" = true ] && [ "$HAS_ADAPTIVECPP" = true ]; then
        echo "Multiple SYCL implementations available."
        echo "Please specify which to use:"
        echo "  $0 intel        - Intel oneAPI (validation + JIT/AOT benchmarks)"
        echo "  $0 adaptivecpp  - AdaptiveCpp (validation + JIT/AOT benchmarks)"
        echo "  $0 all          - Run all tests (both implementations)"
        echo ""
        echo "Each run includes:"
        echo "  - Step 1-6: Validation (correctness, optimization analysis)"
        echo "  - Step 7: Performance benchmarks (JIT vs AOT comparison)"
        echo ""
        echo "Expected benchmark results:"
        echo "  - JIT mode: Should PASS (>5x speedup, specialization constants work)"
        echo "  - AOT mode: Low speedup (<2x, specialization constants don't work)"
        exit 0
    elif [ "$HAS_INTEL" = true ]; then
        IMPL="intel"
        echo "Auto-selecting: Intel oneAPI (validation + benchmarks)"
    else
        IMPL="adaptivecpp"
        echo "Auto-selecting: AdaptiveCpp (validation + benchmarks)"
    fi
fi
echo ""

# Run validation + benchmarks
run_intel() {
    echo "=============================================="
    echo "Running Intel oneAPI Validation + Benchmarks"
    echo "=============================================="
    echo ""
    ./validate-intel.sh
}

run_adaptivecpp() {
    echo "=============================================="
    echo "Running AdaptiveCpp Validation + Benchmarks"
    echo "=============================================="
    echo ""
    ./validate-adaptivecpp.sh
}

case "$IMPL" in
    intel)
        run_intel
        ;;
    adaptivecpp)
        run_adaptivecpp
        ;;
    all)
        if [ "$HAS_INTEL" = true ]; then
            run_intel
            echo ""
            echo ""
        fi
        if [ "$HAS_ADAPTIVECPP" = true ]; then
            run_adaptivecpp
        fi
        ;;
esac

echo ""
echo "=============================================="
echo "Validation & Benchmark Suite Complete"
echo "=============================================="
echo ""
echo "Summary:"
if [ "$IMPL" = "all" ]; then
    echo "  Completed full validation + benchmarks for:"
    echo "    - Intel oneAPI (validation + JIT/AOT benchmarks)"
    echo "    - AdaptiveCpp (validation + JIT/AOT benchmarks)"
elif [ "$IMPL" = "intel" ]; then
    echo "  Completed Intel oneAPI:"
    echo "    - Steps 1-6: Validation (correctness, optimization)"
    echo "    - Step 7: Performance benchmarks (JIT vs AOT)"
elif [ "$IMPL" = "adaptivecpp" ]; then
    echo "  Completed AdaptiveCpp:"
    echo "    - Steps 1-6: Validation (correctness, optimization)"
    echo "    - Step 7: Performance benchmarks (JIT vs AOT)"
fi
echo ""
echo "Results:"
echo "  - All validation steps should PASS"
echo "  - JIT benchmarks should PASS (>5x speedup)"
echo "  - AOT benchmarks should show low speedup (<2x, expected)"
echo ""
