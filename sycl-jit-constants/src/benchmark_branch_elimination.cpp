#include <sycl/sycl.hpp>
#include <iostream>
#include <chrono>
#include <iomanip>
#include "portable_parallel_for.hpp"

struct BenchmarkConfig {
  int multiplier = 0;  // Will test with 0 (should fold to zero) and non-zero values
  int loop_count = 0;  // Will test loop unrolling
};

// Expensive computation - should be eliminated via constant folding when multiplier=0
inline int expensive_computation(int x) {
  int result = x;
  for (int i = 0; i < 1000; ++i) {
    result = (result * 31 + i) ^ (i * i);
    result = result % 997;
    result += (i & 0xFF);
    result ^= (result >> 4);
  }
  return result;
}

int main(int argc, char* argv[]) {
  // Parse command-line arguments to prevent AOT compiler from knowing the values
  // Only the JIT compiler will see these values as specialization constants
  if (argc != 2) {
    std::cerr << "Usage: " << argv[0] << " <multiplier_value>\n";
    std::cerr << "  multiplier_value: 0 (test constant folding) or 1 (baseline)\n";
    return 1;
  }

  int multiplier_value = std::atoi(argv[1]);
  if (multiplier_value < 0) {
    std::cerr << "Error: multiplier_value must be >= 0\n";
    return 1;
  }

  sycl::queue q;

  std::cout << "==============================================\n"
            << "Compile-Time Constant Optimization Benchmark\n"
            << "==============================================\n\n";

  std::cout << "Device: " << q.get_device().get_info<sycl::info::device::name>() << "\n";
  std::cout << "Platform: " << q.get_device().get_platform().get_info<sycl::info::platform::name>() << "\n\n";

  std::cout << "This benchmark tests whether specialization constants are\n";
  std::cout << "treated as compile-time constants (constexpr) by the JIT compiler.\n";
  std::cout << "Key: The AOT compiler does NOT know the multiplier value (passed at runtime).\n";
  std::cout << "     Only the JIT compiler sees it as a specialization constant.\n";
  std::cout << "If JIT treats it as constexpr:\n";
  std::cout << "  - multiplier=0 should fold to 0, eliminating expensive_computation()\n";
  std::cout << "  - multiplier=1 must execute expensive_computation()\n\n";

  std::cout << "Multiplier value (from argv): " << multiplier_value << "\n\n";

  constexpr std::size_t N = 1024 * 1024;  // 1M work items
  constexpr int WARMUP_ITERATIONS = 3;
  constexpr int ITERATIONS = 10;

  int* data = sycl::malloc_shared<int>(N, q);

  // Initialize data
  for (std::size_t i = 0; i < N; ++i) {
    data[i] = 0;
  }

  std::cout << "Warming up GPU...\n";

  // Warm up with the actual configuration we'll test
  BenchmarkConfig warmup_cfg{multiplier_value, 0};
  for (int iter = 0; iter < WARMUP_ITERATIONS; ++iter) {
    portable::parallel_for_1d<BenchmarkConfig>(q, N, warmup_cfg,
      [=](const BenchmarkConfig& cfg, sycl::item<1> it) {
        auto idx = it.get_id(0);
        data[idx] = static_cast<int>(idx);
      });
    q.wait();
  }

  std::cout << "✓ Warm-up complete\n\n";

  // ========================================
  // Run benchmark with runtime-provided multiplier
  // ========================================
  std::cout << "Running benchmark with multiplier = " << multiplier_value << "\n";
  std::cout << "  Testing: result += multiplier * expensive_computation()\n";
  if (multiplier_value == 0) {
    std::cout << "  Expected: If JIT treats multiplier as constexpr,\n";
    std::cout << "            0 * expensive_op() should fold to 0\n";
  } else {
    std::cout << "  Expected: Expensive computation must execute\n";
  }
  std::cout << "\n";

  BenchmarkConfig cfg{multiplier_value, 0};

  // Pre-JIT the exact benchmark kernel once (untimed)
  std::cout << "Pre-JITting exact benchmark kernel (untimed)...\n";
  portable::parallel_for_1d<BenchmarkConfig>(q, N, cfg,
    [=](const BenchmarkConfig& cfg, sycl::item<1> it) {
      auto idx = it.get_id(0);
      int result = static_cast<int>(idx);
      result += cfg.multiplier * expensive_computation(result);
      data[idx] = result;
    });
  q.wait();
  std::cout << "✓ Pre-JIT complete\n\n";

  std::vector<double> times;
  for (int iter = 0; iter < ITERATIONS; ++iter) {
    auto start = std::chrono::high_resolution_clock::now();

    portable::parallel_for_1d<BenchmarkConfig>(q, N, cfg,
      [=](const BenchmarkConfig& cfg, sycl::item<1> it) {
        auto idx = it.get_id(0);
        int result = static_cast<int>(idx);

        // If cfg.multiplier is truly constexpr and = 0, this entire expression
        // should be folded to 0, eliminating expensive_computation() completely
        result += cfg.multiplier * expensive_computation(result);

        data[idx] = result;
      });

    q.wait();

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration<double, std::milli>(end - start).count();
    times.push_back(duration);

    std::cout << "  Iteration " << std::setw(2) << (iter + 1) << ": "
              << std::fixed << std::setprecision(3) << duration << " ms\n";
  }

  double avg_time = 0.0;
  for (auto t : times) avg_time += t;
  avg_time /= times.size();

  std::cout << "\n";
  std::cout << "Average execution time (mult=" << multiplier_value << "): "
            << std::fixed << std::setprecision(3) << avg_time << " ms\n";

  // Verify correctness
  int expected_0, expected_100;
  if (multiplier_value == 0) {
    expected_0 = 0;
    expected_100 = 100;
  } else {
    expected_0 = 0 + multiplier_value * expensive_computation(0);
    expected_100 = 100 + multiplier_value * expensive_computation(100);
  }

  bool correct = (data[0] == expected_0) && (data[100] == expected_100);
  std::cout << "Correctness: " << (correct ? "PASS" : "FAIL") << "\n";
  std::cout << "  data[0] = " << data[0] << " (expected " << expected_0 << ")\n";
  std::cout << "  data[100] = " << data[100] << " (expected " << expected_100 << ")\n";

  sycl::free(data, q);

  return correct ? 0 : 1;
}
