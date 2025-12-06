#!/bin/bash

# Unified script for complete build, test, and validation workflow
# Runs everything automatically without user interaction

set -e

echo "=============================================="
echo "SYCL JIT Constants - Complete Workflow"
echo "Build + Test + Validate All Implementations"
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

# Run all available implementations
RUN_INTEL=$INTEL_AVAILABLE
RUN_ACPP=$ACPP_AVAILABLE

echo "=============================================="
echo "Starting Complete Workflow"
echo "=============================================="
echo ""

INTEL_RESULT=0
ACPP_RESULT=0

# Run Intel validation
if [ $RUN_INTEL -eq 1 ]; then
    echo ""
    echo "▶▶▶ Intel oneAPI SYCL - Full Workflow"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    bash validate-intel.sh
    INTEL_RESULT=$?

    if [ $INTEL_RESULT -eq 0 ]; then
        echo ""
        echo "✓ Intel oneAPI: BUILD + TEST + VALIDATION PASSED"
    else
        echo ""
        echo "✗ Intel oneAPI: FAILED"
    fi
fi

# Run AdaptiveCpp validation
if [ $RUN_ACPP -eq 1 ]; then
    if [ $RUN_INTEL -eq 1 ]; then
        echo ""
        echo "=============================================="
        echo ""
    fi

    echo ""
    echo "▶▶▶ AdaptiveCpp SYCL - Full Workflow"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    bash validate-adaptivecpp.sh
    ACPP_RESULT=$?

    if [ $ACPP_RESULT -eq 0 ]; then
        echo ""
        echo "✓ AdaptiveCpp: BUILD + TEST + VALIDATION PASSED"
    else
        echo ""
        echo "✗ AdaptiveCpp: FAILED"
    fi
fi

echo ""
echo "=============================================="
echo "FINAL SUMMARY - All Implementations"
echo "=============================================="
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_RUN=0

if [ $RUN_INTEL -eq 1 ]; then
    TOTAL_RUN=$((TOTAL_RUN+1))
    if [ $INTEL_RESULT -eq 0 ]; then
        echo "✓ Intel oneAPI SYCL:  COMPLETE WORKFLOW PASSED"
        TOTAL_PASSED=$((TOTAL_PASSED+1))
    else
        echo "✗ Intel oneAPI SYCL:  WORKFLOW FAILED"
        TOTAL_FAILED=$((TOTAL_FAILED+1))
    fi
    # Print validation check summary if available
    if [ -f "validate-intel/summary.txt" ]; then
        echo "  Validation checks (Intel):"
        sed 's/^/    - /' validate-intel/summary.txt
    fi
fi

if [ $RUN_ACPP -eq 1 ]; then
    TOTAL_RUN=$((TOTAL_RUN+1))
    if [ $ACPP_RESULT -eq 0 ]; then
        echo "✓ AdaptiveCpp SYCL:   COMPLETE WORKFLOW PASSED"
        TOTAL_PASSED=$((TOTAL_PASSED+1))
    else
        echo "✗ AdaptiveCpp SYCL:   WORKFLOW FAILED"
        TOTAL_FAILED=$((TOTAL_FAILED+1))
    fi
    # Print validation check summary if available
    if [ -f "validate-adaptivecpp/summary.txt" ]; then
        echo "  Validation checks (AdaptiveCpp):"
        sed 's/^/    - /' validate-adaptivecpp/summary.txt
    fi
fi

echo ""
echo "Tested $TOTAL_RUN implementation(s): $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo ""

if [ $TOTAL_FAILED -eq 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓✓✓ ALL WORKFLOWS COMPLETED SUCCESSFULLY ✓✓✓"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The portable JIT constants implementation:"
    echo "  ✓ Builds correctly on all tested SYCL implementations"
    echo "  ✓ All tests pass with correct runtime behavior"
    echo "  ✓ Compiler optimizations verified (inlining, constant propagation)"
    echo "  ✓ Dead code elimination confirmed"
    echo ""
    echo "Detailed reports available in:"
    if [ $RUN_INTEL -eq 1 ]; then
        echo "  - validate-intel/"
        echo "    • build_report.txt - Compiler optimization reports"
        echo "    • test_output.txt - Runtime test results"
        echo "    • *.ll files - LLVM IR inspection (if available)"
    fi
    if [ $RUN_ACPP -eq 1 ]; then
        echo "  - validate-adaptivecpp/"
        echo "    • build_report.txt - Compiler output"
        echo "    • test_output.txt - Runtime test results"
    fi
    EXIT_CODE=0
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✗✗✗ SOME WORKFLOWS FAILED ✗✗✗"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Please review the detailed reports in validate-*/ directories"
    EXIT_CODE=1
fi

echo ""
echo "=============================================="

exit $EXIT_CODE
