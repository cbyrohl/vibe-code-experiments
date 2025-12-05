#!/bin/bash

# Unified validation script for portable SYCL JIT constants
# Automatically detects available SYCL implementations and runs validation

echo "=============================================="
echo "Portable SYCL JIT Constants"
echo "Unified Validation Script"
echo "=============================================="
echo ""

# Detect available SYCL implementations
INTEL_AVAILABLE=0
ACPP_AVAILABLE=0

# Check for Intel oneAPI
if [ -z "$ONEAPI_ROOT" ]; then
    ONEAPI_ROOT=/opt/intel/oneapi
fi

if [ -f "$ONEAPI_ROOT/setvars.sh" ]; then
    INTEL_AVAILABLE=1
fi

# Check for AdaptiveCpp
if command -v acpp &> /dev/null; then
    ACPP_AVAILABLE=1
fi

# Display available implementations
echo "Detected SYCL implementations:"
if [ $INTEL_AVAILABLE -eq 1 ]; then
    echo "  ✓ Intel oneAPI SYCL"
else
    echo "  ✗ Intel oneAPI SYCL (not found)"
fi

if [ $ACPP_AVAILABLE -eq 1 ]; then
    echo "  ✓ AdaptiveCpp SYCL"
else
    echo "  ✗ AdaptiveCpp SYCL (not found)"
fi
echo ""

# Check if any implementation is available
if [ $INTEL_AVAILABLE -eq 0 ] && [ $ACPP_AVAILABLE -eq 0 ]; then
    echo "Error: No SYCL implementation found!"
    echo ""
    echo "Please install one of the following:"
    echo "  - Intel oneAPI Base Toolkit: https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit.html"
    echo "  - AdaptiveCpp: https://github.com/AdaptiveCpp/AdaptiveCpp"
    exit 1
fi

# Interactive mode if both are available
if [ $INTEL_AVAILABLE -eq 1 ] && [ $ACPP_AVAILABLE -eq 1 ]; then
    echo "Both implementations are available."
    echo ""
    echo "Select validation mode:"
    echo "  1) Intel oneAPI only"
    echo "  2) AdaptiveCpp only"
    echo "  3) Both (run sequentially)"
    echo ""
    read -p "Enter choice [1-3]: " CHOICE

    case $CHOICE in
        1)
            RUN_INTEL=1
            RUN_ACPP=0
            ;;
        2)
            RUN_INTEL=0
            RUN_ACPP=1
            ;;
        3)
            RUN_INTEL=1
            RUN_ACPP=1
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
else
    # Only one implementation available, use it
    RUN_INTEL=$INTEL_AVAILABLE
    RUN_ACPP=$ACPP_AVAILABLE
fi

echo ""
echo "=============================================="
echo "Starting Validation"
echo "=============================================="
echo ""

INTEL_RESULT=0
ACPP_RESULT=0

# Run Intel validation
if [ $RUN_INTEL -eq 1 ]; then
    echo ""
    echo "▶▶▶ Running Intel oneAPI validation..."
    echo ""
    bash validate-intel.sh
    INTEL_RESULT=$?

    if [ $INTEL_RESULT -eq 0 ]; then
        echo ""
        echo "✓ Intel oneAPI validation: PASSED"
    else
        echo ""
        echo "✗ Intel oneAPI validation: FAILED"
    fi
fi

# Run AdaptiveCpp validation
if [ $RUN_ACPP -eq 1 ]; then
    if [ $RUN_INTEL -eq 1 ]; then
        echo ""
        echo "=============================================="
        echo ""
        read -p "Press Enter to continue with AdaptiveCpp validation..."
        echo ""
    fi

    echo ""
    echo "▶▶▶ Running AdaptiveCpp validation..."
    echo ""
    bash validate-adaptivecpp.sh
    ACPP_RESULT=$?

    if [ $ACPP_RESULT -eq 0 ]; then
        echo ""
        echo "✓ AdaptiveCpp validation: PASSED"
    else
        echo ""
        echo "✗ AdaptiveCpp validation: FAILED"
    fi
fi

echo ""
echo "=============================================="
echo "Final Summary"
echo "=============================================="
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0

if [ $RUN_INTEL -eq 1 ]; then
    if [ $INTEL_RESULT -eq 0 ]; then
        echo "✓ Intel oneAPI SYCL:  VALIDATION PASSED"
        ((TOTAL_PASSED++))
    else
        echo "✗ Intel oneAPI SYCL:  VALIDATION FAILED"
        ((TOTAL_FAILED++))
    fi
fi

if [ $RUN_ACPP -eq 1 ]; then
    if [ $ACPP_RESULT -eq 0 ]; then
        echo "✓ AdaptiveCpp SYCL:   VALIDATION PASSED"
        ((TOTAL_PASSED++))
    else
        echo "✗ AdaptiveCpp SYCL:   VALIDATION FAILED"
        ((TOTAL_FAILED++))
    fi
fi

echo ""

if [ $TOTAL_FAILED -eq 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓✓✓ ALL VALIDATIONS PASSED ✓✓✓"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The portable JIT constants implementation works correctly"
    echo "on all tested SYCL implementations!"
    echo ""
    echo "Results demonstrate:"
    echo "  • Correct backend detection at compile time"
    echo "  • Proper JIT constant propagation"
    echo "  • Compiler optimization (inlining, dead code elimination)"
    echo "  • Correct runtime behavior across implementations"
    echo ""
    echo "Detailed reports available in:"
    if [ $RUN_INTEL -eq 1 ]; then
        echo "  - validate-intel/"
    fi
    if [ $RUN_ACPP -eq 1 ]; then
        echo "  - validate-adaptivecpp/"
    fi
    EXIT_CODE=0
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✗✗✗ SOME VALIDATIONS FAILED ✗✗✗"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Please review the detailed reports in validate-*/ directories"
    EXIT_CODE=1
fi

echo ""
echo "=============================================="

exit $EXIT_CODE
