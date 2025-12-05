cmake_minimum_required(VERSION 3.22)
project(SyclJitConstants VERSION 0.1 LANGUAGES CXX)

# C++20 standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Auto-detect SYCL implementation
if (CMAKE_CXX_COMPILER_ID MATCHES "IntelLLVM")
    set(INTEL_SYCL ON)
    message(STATUS "Detected Intel oneAPI SYCL compiler")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsycl")

    # Optional: architecture-specific optimizations
    if (CMAKE_BUILD_TYPE MATCHES "Release")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -xHost")
    endif()
else()
    # Assume AdaptiveCpp (acpp/hipSYCL)
    find_package(AdaptiveCpp CONFIG REQUIRED)
    message(STATUS "Using AdaptiveCpp SYCL implementation")

    if (CMAKE_BUILD_TYPE MATCHES "Release")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
    endif()
endif()

# Debug flags
if (CMAKE_BUILD_TYPE MATCHES "Debug")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -O0")
endif()

# Main executable
add_executable(sycl_jit_example src/main.cpp)

# Include directories
target_include_directories(sycl_jit_example PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

# Link SYCL for AdaptiveCpp
if (NOT INTEL_SYCL)
    add_sycl_to_target(TARGET sycl_jit_example)
endif()

# Validation test executable
add_executable(validation_test src/validation_test.cpp)

target_include_directories(validation_test PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

if (NOT INTEL_SYCL)
    add_sycl_to_target(TARGET validation_test)
endif()
