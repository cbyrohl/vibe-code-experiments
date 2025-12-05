#pragma once
#include "portable_spec.hpp"
#include <concepts>

namespace portable {

template <typename T, typename Kernel>
concept KernelCallable = requires(Kernel k, const T& cfg, sycl::item<1> it) {
  { k(cfg, it) };
};

template <Specializable T, typename Kernel>
  requires KernelCallable<T, Kernel>
sycl::event parallel_for_1d(sycl::queue& q,
                             std::size_t N,
                             const T& cfg,
                             Kernel&& kernel_body)
{
#ifdef PORTABLE_BACKEND_ADAPTIVECPP
  auto cfg_arg = spec<T>::make_arg(cfg);
  return q.parallel_for(sycl::range<1>(N), [=](sycl::item<1> it) {
    kernel_body(spec<T>::get(cfg_arg), it);
  });
#else
  return q.submit([&](sycl::handler& h) {
    spec<T>::set(h, cfg);
    h.parallel_for(sycl::range<1>(N), [=](sycl::item<1> it, sycl::kernel_handler kh) {
      kernel_body(spec<T>::get(kh), it);
    });
  });
#endif
}

template <Specializable T, typename Kernel>
  requires KernelCallable<T, Kernel>
void parallel_for_1d_sync(sycl::queue& q,
                           std::size_t N,
                           const T& cfg,
                           Kernel&& kernel_body)
{
  parallel_for_1d(q, N, cfg, std::forward<Kernel>(kernel_body)).wait();
}

} // namespace portable
