#pragma once
#include <sycl/sycl.hpp>
#include <concepts>

namespace portable {

#if defined(__ACPP__) || defined(__ADAPTIVECPP__) || defined(__HIPSYCL__)
  #define PORTABLE_BACKEND_ADAPTIVECPP 1
#endif

template <class T>
struct spec;

template <typename T>
concept Specializable = std::semiregular<T> && requires {
  typename spec<T>::device_arg;
};

#ifdef PORTABLE_BACKEND_ADAPTIVECPP

template <class T>
struct spec {
  using device_arg = sycl::specialized<T>;

  template <class Handler>
  static void set(Handler&, const T&) {}

  static constexpr device_arg make_arg(const T& v) noexcept {
    return device_arg{v};
  }

  static constexpr T get(const device_arg& arg) noexcept {
    return arg;
  }
};

#else

template <class T>
struct spec {
  using device_arg = sycl::kernel_handler;

  inline static constexpr sycl::specialization_id<T> id{T{}};

  template <class Handler>
  static void set(Handler& h, const T& v) {
    h.template set_specialization_constant<id>(v);
  }

  static device_arg make_arg(const T&) {
    return {};
  }

  static T get(device_arg kh) {
    return kh.template get_specialization_constant<id>();
  }
};

#endif

} // namespace portable
