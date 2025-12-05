#include <sycl/sycl.hpp>
#include <iostream>
#include <chrono>
#include <span>
#include <algorithm>
#include <ranges>
#include "portable_parallel_for.hpp"

struct BranchConfig {
  bool enable_feature_a = false;
  bool enable_feature_b = false;
  int mode = 0;
};

struct LoopConfig {
  int unroll_factor = 1;
};

struct ArrayConfig {
  int array_size = 16;
};

template <typename T>
class usm_ptr {
  T* ptr_;
  sycl::queue* q_;
public:
  usm_ptr(std::size_t n, sycl::queue& q)
    : ptr_(sycl::malloc_shared<T>(n, q)), q_(&q) {}
  ~usm_ptr() { if (ptr_) sycl::free(ptr_, *q_); }
  usm_ptr(const usm_ptr&) = delete;
  usm_ptr& operator=(const usm_ptr&) = delete;
  usm_ptr(usm_ptr&& other) noexcept : ptr_(other.ptr_), q_(other.q_) { other.ptr_ = nullptr; }
  usm_ptr& operator=(usm_ptr&& other) noexcept {
    if (this != &other) {
      if (ptr_) sycl::free(ptr_, *q_);
      ptr_ = other.ptr_;
      q_ = other.q_;
      other.ptr_ = nullptr;
    }
    return *this;
  }
  T* get() noexcept { return ptr_; }
  const T* get() const noexcept { return ptr_; }
  T& operator[](std::size_t i) noexcept { return ptr_[i]; }
  const T& operator[](std::size_t i) const noexcept { return ptr_[i]; }
};

template <typename Config, typename KernelFn, typename ValidateFn>
bool run_test(sycl::queue& q, std::string_view name, const Config& cfg, std::size_t N,
              KernelFn&& kernel, ValidateFn&& validate) {
  std::cout << "=== " << name << " ===\n";

  usm_ptr<int> data(N, q);
  int* data_ptr = data.get();

  auto start = std::chrono::high_resolution_clock::now();
  portable::parallel_for_1d_sync<Config>(q, N, cfg,
    [kernel = std::forward<KernelFn>(kernel), data_ptr](const Config& cfg, sycl::item<1> it) {
      data_ptr[it.get_id(0)] = kernel(cfg, it);
    });
  auto duration = std::chrono::duration_cast<std::chrono::microseconds>(
    std::chrono::high_resolution_clock::now() - start);

  bool passed = validate(data);

  std::cout << "  Execution time: " << duration.count() << " μs\n"
            << "  Result validation: " << (passed ? "PASS" : "FAIL") << "\n\n";

  return passed;
}

[[nodiscard]] bool test_branch_elimination(sycl::queue& q) {
  BranchConfig cfg_a{true, false, 1};
  constexpr std::size_t N = 1024 * 1024;

  return run_test(q, "Test 1: Branch Elimination", cfg_a, N,
    [](const BranchConfig& cfg, sycl::item<1> it) {
      auto i = it.get_id(0);
      int result = cfg.enable_feature_a ? int(i) * 2 : int(i) * 3;

      if (cfg.enable_feature_b) {
        for (int j = 0; j < 100; ++j) {
          result += j * j;
        }
      }

      switch (cfg.mode) {
        case 0: result += 10; break;
        case 1: result += 20; break;
        case 2: result += 30; break;
      }

      return result;
    },
    [](const usm_ptr<int>& data) {
      bool correct = (data[0] == 20) && (data[1] == 22) && (data[10] == 40);
      if (correct) {
        std::cout << "  Expected: feature_a enabled, mode=1 → i*2 + 20\n"
                  << "  Sample results: [0]=" << data[0]
                  << ", [1]=" << data[1]
                  << ", [10]=" << data[10] << "\n";
      }
      return correct;
    }
  );
}

[[nodiscard]] bool test_loop_unrolling(sycl::queue& q) {
  LoopConfig cfg{4};
  constexpr std::size_t N = 1024 * 1024;

  return run_test(q, "Test 2: Loop Unrolling", cfg, N,
    [](const LoopConfig& cfg, sycl::item<1> it) {
      auto i = it.get_id(0);
      int sum = 0;

      #pragma unroll
      for (int j = 0; j < 4; ++j) {
        if (j < cfg.unroll_factor) {
          sum += j * int(i);
        }
      }

      return sum;
    },
    [](const usm_ptr<int>& data) {
      bool correct = (data[0] == 0) && (data[1] == 6) && (data[10] == 60);
      if (correct) {
        std::cout << "  Expected: sum of 0*i + 1*i + 2*i + 3*i = 6*i\n"
                  << "  Sample results: [0]=" << data[0]
                  << ", [1]=" << data[1]
                  << ", [10]=" << data[10] << "\n";
      }
      return correct;
    }
  );
}

[[nodiscard]] bool test_constant_propagation(sycl::queue& q) {
  ArrayConfig cfg{16};
  constexpr std::size_t N = 1024;

  return run_test(q, "Test 3: Constant Propagation", cfg, N,
    [](const ArrayConfig& cfg, sycl::item<1> it) {
      int sum = 0;
      #pragma unroll
      for (int j = 0; j < 16; ++j) {
        if (j < cfg.array_size) {
          sum += j;
        }
      }
      return sum;
    },
    [](const usm_ptr<int>& data) {
      bool correct = (data[0] == 120) && (data[100] == 120);
      if (correct) {
        std::cout << "  Expected: sum of 0..15 = 120\n"
                  << "  Sample results: [0]=" << data[0]
                  << ", [100]=" << data[100] << "\n"
                  << "  Note: Demonstrates constant propagation enabling loop optimization\n";
      }
      return correct;
    }
  );
}

int main() {
  try {
    sycl::queue q;

    std::cout << "JIT Constants Validation Tests\n"
              << "================================\n"
              << "Device: " << q.get_device().get_info<sycl::info::device::name>() << "\n"
              << "Platform: " << q.get_device().get_platform().get_info<sycl::info::platform::name>() << "\n\n";

    bool test1 = test_branch_elimination(q);
    bool test2 = test_loop_unrolling(q);
    bool test3 = test_constant_propagation(q);

    bool all_passed = test1 && test2 && test3;

    std::cout << "================================\n"
              << "Result: " << (all_passed ? "ALL TESTS PASSED" : "SOME TESTS FAILED") << "\n"
              << "\nTo verify optimization, examine generated assembly/IR:\n"
              << "  Intel: Add -fsycl-device-code-split=per_kernel -Rpass=inline\n"
              << "  For IR: Add -fsave-optimization-record\n";

    return all_passed ? 0 : 1;

  } catch (sycl::exception const& e) {
    std::cerr << "SYCL exception: " << e.what() << "\n";
    return 1;
  }
}
