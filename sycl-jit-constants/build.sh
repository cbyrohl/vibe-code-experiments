#!/bin/bash

echo "Portable SYCL JIT Constants - Build Script"
echo "=========================================="
echo ""
echo "Select SYCL implementation:"
echo "  1) Intel oneAPI SYCL"
echo "  2) AdaptiveCpp SYCL"
echo ""
read -p "Enter choice [1-2]: " choice

case $choice in
    1)
        echo "Building with Intel oneAPI..."
        bash build-intel.sh
        ;;
    2)
        echo "Building with AdaptiveCpp..."
        bash build-adaptivecpp.sh
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
