// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
#pragma once
#include "ntt_pr.hpp"

constexpr const std::size_t NumberOfFFTPoints = 8192;
constexpr const std::size_t P = 998244353;
constexpr const std::size_t G = 15311432;
constexpr const std::size_t M = (1<<23);

typedef hls::fft::gf_value<std::uint64_t, P> FFTElement;

void run_multiply_polynomial(const FFTElement input_a[NumberOfFFTPoints], const FFTElement input_b[NumberOfFFTPoints], FFTElement output[NumberOfFFTPoints]);
void run_multiply_polynomial_pretranformed(const FFTElement input_a[NumberOfFFTPoints], const FFTElement input_b[NumberOfFFTPoints], FFTElement output[NumberOfFFTPoints]);
