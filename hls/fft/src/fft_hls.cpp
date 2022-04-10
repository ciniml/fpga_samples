// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

#include "fft.hpp"

typedef float FFTElement;
constexpr const std::size_t NumberOfFFTPoints = 16384;

using namespace hls::fft;

static void convert_from_real_to_complex(const FFTElement input[NumberOfFFTPoints], InterleavedArray<complex<FFTElement>, NumberOfFFTPoints>& output)
{
    for(std::size_t i = 0; i < NumberOfFFTPoints; i++) {
        output[i] = input[i];
    }
}
static void convert_from_complex_to_real(const InterleavedArray<complex<FFTElement>, NumberOfFFTPoints>& input, FFTElement output[NumberOfFFTPoints])
{
    for(std::size_t i = 0; i < NumberOfFFTPoints; i++) {
        output[i] = std::real(input[i]);
    }
}

void run_fft(const FFTElement input[NumberOfFFTPoints], FFTElement output[NumberOfFFTPoints])
{
#pragma HLS INTERFACE mode=m_axi port=input
#pragma HLS INTERFACE mode=m_axi port=output
#pragma HLS INTERFACE mode=ap_ctrl_chain port=return
#pragma HLS DATAFLOW
	InterleavedArray<complex<FFTElement>, NumberOfFFTPoints> input_complex;
	InterleavedArray<complex<FFTElement>, NumberOfFFTPoints> output_complex;
	cooley_tukey_fft<complex<FFTElement>, NumberOfFFTPoints> fft;

	convert_from_real_to_complex(input, input_complex);
    fft.run(input_complex, output_complex);
    convert_from_complex_to_real(output_complex, output);
}
