// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

#include "ntt_pr.hpp"
#include <ap_int.h>

constexpr const std::size_t NumberOfFFTPoints = 128;
constexpr const std::size_t P = 998244353;
constexpr const std::size_t G = 15311432;
constexpr const std::size_t M = (1<<23);

using namespace hls::fft;
using namespace hls::ntt_pr;

typedef gf_value<std::uint64_t, P> FFTElement;

static void read_memory(const FFTElement input[NumberOfFFTPoints], InterleavedArray<FFTElement, NumberOfFFTPoints>& output)
{
    for(std::size_t i = 0; i < NumberOfFFTPoints; i++) {
        output[i] = input[i];
    }
}
static void write_memory(const InterleavedArray<FFTElement, NumberOfFFTPoints>& input, FFTElement output[NumberOfFFTPoints])
{
    for(std::size_t i = 0; i < NumberOfFFTPoints; i++) {
        output[i] = input[i];
    }
}

static multiply_polynomial<FFTElement, NumberOfFFTPoints, M, P, G> mp;

void run_multiply_polynomial(const FFTElement input_a[NumberOfFFTPoints], const FFTElement input_b[NumberOfFFTPoints], FFTElement output[NumberOfFFTPoints])
{
#pragma HLS INTERFACE mode=m_axi port=input_a bundle=input_a
#pragma HLS INTERFACE mode=m_axi port=input_b bundle=input_b
#pragma HLS INTERFACE mode=m_axi port=output bundle=output
#pragma HLS INTERFACE mode=ap_ctrl_chain port=return
#pragma HLS DATAFLOW
    InterleavedArray<FFTElement, NumberOfFFTPoints, 1> input_a_buffer;
    InterleavedArray<FFTElement, NumberOfFFTPoints, 1> input_b_buffer;
    InterleavedArray<FFTElement, NumberOfFFTPoints, 1> output_buffer;
    
    read_memory(input_a, input_a_buffer);
    read_memory(input_b, input_b_buffer);
    mp.run(input_a_buffer, input_b_buffer, output_buffer);
    write_memory(output_buffer, output);
}
