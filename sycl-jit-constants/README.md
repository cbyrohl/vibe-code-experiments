# Portable SYCL JIT Constants Example

Minimal example demonstrating portable JIT (Just-In-Time) constants across Intel oneAPI SYCL and AdaptiveCpp SYCL implementations.

## What are JIT Constants?

JIT constants allow you to pass configuration values _at program run time_ to kernels that will be at constants at _kernel compile time_, potentially enabling better optimizations.

- **Intel oneAPI SYCL**: Uses `sycl::specialization_id<T>` and `kernel_handler`
- **AdaptiveCpp**: Uses `sycl::specialized<T>` as kernel parameter

This project/experiment aims to provides a unified wrapper that works with both.

## Project Structure

- `include/portable_spec.hpp` - Core wrapper for JIT constants
- `include/portable_parallel_for.hpp` - Convenience wrapper for parallel_for with configs
- `src/main.cpp` - Example usage with two different config types

## Requirements

### Intel oneAPI SYCL
- Intel oneAPI Base Toolkit (tested on 2025.3)
- Compiler: `icpx`

### AdaptiveCpp SYCL
- AdaptiveCpp (tested on 25.02.0)
- Compiler: `acpp`
- Backend support: OMP (CPU), CUDA (NVIDIA), HIP (AMD)

## Building

### Quick Start

Use the interactive build script:

```bash
bash build.sh
```

### Intel oneAPI

```bash
# Source Intel oneAPI environment
source /opt/intel/oneapi/setvars.sh

# Build
bash build-intel.sh

# Run
./build-intel/sycl_jit_example
```

### AdaptiveCpp

```bash
# Ensure acpp is in PATH
export PATH=/path/to/AdaptiveCpp/bin:$PATH

# Build (defaults to OMP backend)
bash build-adaptivecpp.sh

# For NVIDIA GPU:
# Edit build-adaptivecpp.sh and set: -DACPP_TARGETS="cuda:sm_80"

# For AMD GPU:
# Edit build-adaptivecpp.sh and set: -DACPP_TARGETS="hip:gfx90a"

# Run
./build-adaptivecpp/sycl_jit_example
```

### Manual CMake Build

```bash
# Intel oneAPI
mkdir build && cd build
cmake .. -DCMAKE_CXX_COMPILER=icpx -DCMAKE_BUILD_TYPE=Release
cmake --build .

# AdaptiveCpp
mkdir build && cd build
cmake .. -DCMAKE_CXX_COMPILER=acpp -DCMAKE_BUILD_TYPE=Release
cmake --build .
```

## Usage Example

```cpp
#include "portable_parallel_for.hpp"

struct MyConfig {
  int iterations;
  float threshold;
};

sycl::queue q;
int* data = sycl::malloc_shared<int>(N, q);

MyConfig cfg{10, 0.5f};

portable::parallel_for_1d<MyConfig>(q, N, cfg,
  [=](const MyConfig& c, sycl::item<1> it) {
    auto i = it.get_id(0);
    // Use c.iterations and c.threshold here
    data[i] = c.iterations * i;
  }
);
```

## How It Works

The wrapper detects the SYCL implementation at compile time:

1. **AdaptiveCpp path**: Wraps config in `sycl::specialized<T>` and passes as lambda capture
2. **SYCL 2020 path**: Uses `handler.set_specialization_constant()` with `kernel_handler`

Both paths provide the same user-facing API with identical kernel signatures.

## Example Output

```
Running on: Intel(R) UHD Graphics [0x9a49]
Platform: Intel(R) Level-Zero

Test 1: ConfigA (use_fast=true, factor=3)
  Result: PASS

Test 2: ConfigB (tile_x=4, tile_y=2)
  Result: PASS

Overall: ALL TESTS PASSED
```

## Architecture

### Backend Detection

The project uses two-stage detection:

1. **CMake level** (`CMakeLists.txt`):
   - Checks `CMAKE_CXX_COMPILER_ID MATCHES "IntelLLVM"` for Intel oneAPI
   - Falls back to AdaptiveCpp with `find_package(AdaptiveCpp)`

2. **Code level** (`portable_spec.hpp`):
   - Checks `__ACPP__`, `__ADAPTIVECPP__`, or `__HIPSYCL__` macros
   - If not present, assumes SYCL 2020 standard (Intel oneAPI)

### Key Differences

| Aspect | Intel oneAPI | AdaptiveCpp |
|--------|-------------|-------------|
| JIT constant type | `sycl::specialization_id<T>` | `sycl::specialized<T>` |
| Setting value | `handler.set_specialization_constant()` | Passed as lambda capture |
| Kernel access | Via `kernel_handler` parameter | Direct access from capture |
| CMake integration | Built-in with `-fsycl` | Requires `add_sycl_to_target()` |

## Validating Optimizations

To verify that JIT constants are actually being optimized by the compiler, use the provided validation scripts:

### Automated Validation Scripts

```bash
# Unified validation (detects available SYCL implementations)
./validate.sh

# Intel oneAPI specific validation
./validate-intel.sh

# AdaptiveCpp specific validation
./validate-adaptivecpp.sh
```

These scripts perform comprehensive validation including:
- ✓ Compiler optimization reports (inlining, vectorization)
- ✓ Runtime correctness tests
- ✓ LLVM IR inspection (when available)
- ✓ Performance measurements
- ✓ Code size analysis

For manual validation and detailed methodology, see [VALIDATION.md](VALIDATION.md)

## Project Files

- **Core Implementation**
  - `include/portable_spec.hpp` - JIT constants wrapper (Intel/AdaptiveCpp)
  - `include/portable_parallel_for.hpp` - Convenience parallel_for wrapper
  - `src/main.cpp` - Basic example with two config types
  - `src/validation_test.cpp` - Optimization validation tests

- **Build System**
  - `CMakeLists.txt` - Auto-detecting CMake configuration
  - `build.sh` - Interactive build script
  - `build-intel.sh` - Intel oneAPI build
  - `build-adaptivecpp.sh` - AdaptiveCpp build
  - `build-intel-with-reports.sh` - Intel build with optimization reports

- **Documentation**
  - `README.md` - This file
  - `VALIDATION.md` - Detailed optimization validation guide

## References

- [SYCL 2020 Specification](https://www.khronos.org/registry/SYCL/)
- [Intel oneAPI Documentation](https://www.intel.com/content/www/us/en/docs/oneapi/programming-guide/current/overview.html)
- [AdaptiveCpp Documentation](https://github.com/AdaptiveCpp/AdaptiveCpp)
