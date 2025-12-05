#include <sycl/sycl.hpp>
#include <iostream>
#include <cassert>
#include <memory>
#include <span>
#include <algorithm>
#include <ranges>
#include "portable_parallel_for.hpp"

struct ConfigA {
  bool use_fast = false;
  int  factor   = 1;
};

struct ConfigB {
  int  tile_x = 1;
  int  tile_y = 1;
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
  T& operator[](std::size_t i) noexcept { return ptr_[i]; }
};

int main() {
  try {
    sycl::queue q;

    std::cout << "Running on: " << q.get_device().get_info<sycl::info::device::name>() << "\n"
              << "Platform: " << q.get_device().get_platform().get_info<sycl::info::platform::name>() << "\n\n";

    constexpr std::size_t N = 16;
    usm_ptr<int> dataA(N, q);
    usm_ptr<int> dataB(N, q);

    std::ranges::fill_n(dataA.get(), N, -1);
    std::ranges::fill_n(dataB.get(), N, -1);

    ConfigA a{true, 3};
    ConfigB b{4, 2};

    auto validate = [](std::span<const int> data, auto expected_fn, std::string_view name) {
      for (std::size_t i = 0; i < data.size(); ++i) {
        if (data[i] != expected_fn(i)) {
          std::cerr << "  " << name << " FAIL at index " << i
                    << ": expected " << expected_fn(i)
                    << ", got " << data[i] << "\n";
          return false;
        }
      }
      return true;
    };

    std::cout << "Test 1: ConfigA (use_fast=true, factor=3)\n";
    int* ptrA = dataA.get();
    portable::parallel_for_1d_sync<ConfigA>(q, N, a,
      [=](const ConfigA& cfg, sycl::item<1> it) {
        auto i = it.get_id(0);
        int base = cfg.use_fast ? cfg.factor : 1;
        ptrA[i] = base * int(i);
      }
    );

    bool test1_passed = validate(
      std::span<const int>(dataA.get(), N),
      [&a](std::size_t i) { return (a.use_fast ? a.factor : 1) * int(i); },
      "Test1"
    );
    std::cout << "  Result: " << (test1_passed ? "PASS" : "FAIL") << "\n\n";

    std::cout << "Test 2: ConfigB (tile_x=4, tile_y=2)\n";
    int* ptrB = dataB.get();
    portable::parallel_for_1d_sync<ConfigB>(q, N, b,
      [=](const ConfigB& cfg, sycl::item<1> it) {
        auto i = it.get_id(0);
        int tile_area = cfg.tile_x * cfg.tile_y;
        ptrB[i] = tile_area + int(i);
      }
    );

    bool test2_passed = validate(
      std::span<const int>(dataB.get(), N),
      [&b](std::size_t i) { return (b.tile_x * b.tile_y) + int(i); },
      "Test2"
    );
    std::cout << "  Result: " << (test2_passed ? "PASS" : "FAIL") << "\n\n";

    bool all_passed = test1_passed && test2_passed;
    std::cout << "Overall: " << (all_passed ? "ALL TESTS PASSED" : "SOME TESTS FAILED") << "\n";

    return all_passed ? 0 : 1;

  } catch (sycl::exception const& e) {
    std::cerr << "SYCL exception: " << e.what() << "\n";
    return 1;
  }
}
