// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
#include "ntt_pr_hls.hpp"
#include <cstdint>
#include <iostream>

using namespace hls::fft;
using namespace hls::ntt_pr;

static FFTElement input_a[NumberOfFFTPoints];
static FFTElement input_b[NumberOfFFTPoints];
static FFTElement output[NumberOfFFTPoints];

int main(int argc, char* argv[])
{
    for(std::size_t i = 0; i < NumberOfFFTPoints; i++) {
        input_a[i] = i;
        input_b[i] = NumberOfFFTPoints - i;
    }

    run_multiply_polynomial(input_a, input_b, output);

    for(std::size_t i = 0; i < NumberOfFFTPoints; i++) {
        std::cout << output[i] << ",";
    }
    std::cout << std::endl;

    return 0;
}
