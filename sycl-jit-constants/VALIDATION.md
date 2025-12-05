# Validating JIT Constant Optimization

This document explains how to verify that JIT constants are actually being used as compile-time constants and enabling optimizations in your SYCL kernels.

## Why Validation Matters

JIT (Just-In-Time) constants should allow the compiler to:
- **Eliminate dead branches** - Remove code paths not taken
- **Constant propagation** - Replace variables with their known values
- **Loop unrolling** - Unroll loops with constant bounds
- **Array sizing** - Use constants for stack array allocation
- **Reduce register pressure** - Fewer runtime variables needed

## Validation Methods

### Method 1: Runtime Validation Tests

Run the validation test program that includes optimization-sensitive code:

```bash
# Build and run validation tests
bash build-intel.sh
./sycl_jit_example        # Basic functionality test
./validation_test         # Optimization validation tests
```

The `validation_test` program includes three tests:

1. **Branch Elimination Test**: Uses config to select code paths. If optimized correctly, dead branches should be eliminated.
2. **Loop Unrolling Test**: Tests whether constant loop bounds enable unrolling.
3. **Constant Array Size Test**: Verifies that constants can be used for stack array sizing.

Expected output:
```
=== Test 1: Branch Elimination ===
  Execution time: XXX μs
  Result validation: PASS
  ...

=== Test 2: Loop Unrolling ===
  Execution time: XXX μs
  Result validation: PASS
  ...

=== Test 3: Constant Array Sizing ===
  Result validation: PASS
  Note: Stack array allocation succeeded (size was constant)
```

### Method 2: Compiler Optimization Reports

Build with optimization reporting enabled:

```bash
bash build-intel-with-reports.sh
```

This adds compiler flags:
- `-Rpass=inline` - Reports when functions are inlined
- `-Rpass-analysis=loop-vectorize` - Reports loop vectorization decisions
- `-fsycl-device-code-split=per_kernel` - Generates separate kernel objects

The build output will show optimization decisions. Look for:
```
remark: 'function_name' inlined into 'kernel_name'
remark: vectorized loop (vectorization width: X)
```

The optimization report is saved to `build-intel-reports/optimization_report.txt`.

### Method 3: Inspect Generated SPIR-V/Assembly

#### Intel oneAPI - Generate Intermediate Representations

```bash
# Generate SPIR-V and save all intermediate files
icpx -fsycl -fsycl-device-code-split=per_kernel -save-temps=obj \
     -I./include -c src/validation_test.cpp -o validation_test.o

# This creates:
# - *.bc files (LLVM bitcode)
# - *.spv files (SPIR-V)
# - *.ll files (LLVM IR - human readable)
```

#### Examine LLVM IR for Optimizations

```bash
# Convert bitcode to readable LLVM IR
llvm-dis validation_test-*.bc -o kernel.ll

# Look for evidence of optimization:
grep -A 10 "define.*kernel" kernel.ll
```

**Signs of good optimization in LLVM IR:**
- Constant values instead of loads from memory
- Fewer branches (`br` instructions)
- Simplified arithmetic
- Absence of dead code paths

#### Example - Optimized vs Unoptimized

**Unoptimized** (config as runtime variable):
```llvm
%1 = load i32, i32* %config_ptr
%2 = icmp eq i32 %1, 0
br i1 %2, label %branch_a, label %branch_b
```

**Optimized** (config as constant):
```llvm
; Branch eliminated, only one path remains
br label %branch_a
```

### Method 4: Performance Comparison

Compare performance with JIT constants vs runtime parameters:

```cpp
// Baseline: Runtime parameter (no optimization)
void kernel_runtime(int* data, int factor) {
  data[i] = (factor == 3) ? i * 3 : i * 1;
}

// Optimized: JIT constant (should be faster)
portable::parallel_for_1d<Config>(q, N, config, [=](const Config& cfg, ...) {
  data[i] = (cfg.factor == 3) ? i * 3 : i * 1;
});
```

If JIT constants work correctly, the optimized version should be faster due to:
- Branch elimination
- Constant propagation
- Better instruction scheduling

### Method 5: Platform-Specific Tools

#### Intel VTune Profiler

```bash
# Collect hotspots and microarchitecture data
vtune -collect hotspots -result-dir vtune_results -- ./validation_test

# View results
vtune-gui vtune_results
```

Look for:
- Lower instruction counts in optimized kernels
- Better IPC (Instructions Per Cycle)
- Fewer branch mispredictions

#### Intel Advisor

```bash
# Roofline analysis
advisor --collect=roofline --project-dir=advisor_results -- ./validation_test

# View results
advisor-gui advisor_results
```

#### AdaptiveCpp - Check Optimizations

For AdaptiveCpp, examine the generated PTX (NVIDIA) or assembly (AMD):

```bash
# Build with verbose output
acpp -v --acpp-targets="cuda:sm_80" -I./include src/validation_test.cpp

# This will show the underlying compilation commands
# Look for generated .ptx or .cubin files
```

Examine PTX for constant propagation:
```bash
# Look for mov instructions with immediate values (constants)
grep "mov.*immediate" kernel.ptx
```

## Intel oneAPI Specific: AOT Compilation

For ahead-of-time (AOT) compilation with specific devices:

```bash
# Compile for specific GPU architecture
icpx -fsycl -fsycl-targets=spir64_gen -Xsycl-target-backend \
     "-device pvc" -I./include src/validation_test.cpp -o validation_test

# This generates optimized code for the target device
# Specialization constants are resolved at AOT compile time
```

## What to Look For

### ✅ Good Signs (Optimization Working)

1. **Compiler reports**: Inlining and vectorization messages
2. **LLVM IR**: Direct branches, no conditional loads from config
3. **Performance**: Faster execution vs runtime parameters
4. **Code size**: Smaller kernels (dead code eliminated)
5. **Assembly**: Immediate values instead of memory loads

### ❌ Bad Signs (Not Optimized)

1. **LLVM IR**: Multiple branches based on config loads
2. **Performance**: Same speed as runtime parameters
3. **Assembly**: Config values loaded from memory
4. **Warnings**: "Cannot determine constant value"

## Example: Manual IR Inspection

Create a simple test kernel and inspect the IR:

```bash
# Create minimal test file
cat > test_constant.cpp << 'EOF'
#include <sycl/sycl.hpp>
#include "portable_parallel_for.hpp"

struct Config { int value; };

int main() {
  sycl::queue q;
  int* data = sycl::malloc_shared<int>(100, q);
  Config cfg{42};

  portable::parallel_for_1d<Config>(q, 100, cfg,
    [=](const Config& c, sycl::item<1> it) {
      data[it.get_id(0)] = c.value * 2;
    });

  sycl::free(data, q);
}
EOF

# Compile and save IR
icpx -fsycl -save-temps=obj -I./include test_constant.cpp

# Examine IR
llvm-dis test_constant-*.bc -o test.ll
cat test.ll | grep -A 20 "define.*kernel"
```

You should see `mul i32 %index, 84` (constant folded) instead of loads and runtime multiplication.

## Summary

The most reliable validation methods are:

1. **Quickest**: Run `validation_test` and verify all tests pass
2. **Most informative**: Build with `-Rpass=inline` and review optimization report
3. **Most thorough**: Inspect LLVM IR for constant propagation
4. **Most practical**: Performance comparison vs runtime parameters

If optimizations aren't working, check:
- Are you using Release build? (`-DCMAKE_BUILD_TYPE=Release`)
- Is the config type truly being specialized? (Check preprocessor macros)
- Are there any warnings during compilation?
