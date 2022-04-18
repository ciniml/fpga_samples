// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// @file  ntt_pr.hpp
// @brief polynomial ring multiplication using NTT.
//        The algorithm is described in https://tex2e.github.io/blog/crypto/ntt-polynomial-multiplication 
#pragma once

#include "fft.hpp"

#ifndef __SYNTHESIS__
#include <iostream>
#endif

namespace hls::ntt_pr {


/**
 * @brief Twiddle factor for number theorem transform (NTT) on GF(P)
 * 
 * @tparam T Type to represent GF(P) value. Usually it is gf_value<T>
 * @tparam N Number of FFT points.
 * @tparam P A prime number
 * @tparam G The base root of the prime root.
 * @tparam A The power factor of the prime root. G^A is used as the prime root of this twiddle factor.
 */

template <typename T, std::size_t N, std::uint64_t P, std::uint64_t G, bool INVERSE>
struct NTTPolynomialRingFactor
{
    static constexpr auto make_table()
    {
        std::array<T, N> table;
        constexpr auto phi = T(hls::fft::ensure_constexpr<typename T::value_type, INVERSE ? T(G).sqrt().reciprocal().value : T(G).sqrt().value>::value);
        T phi_i = T(1);
        for(std::size_t i = 0; i < N; i++, phi_i *= phi ) {
            table[i] = phi_i;
        }
        return table;
    }

    std::array<T, N> table = make_table();
    
    T operator[](std::size_t i) const {
        return this->table[i];
    }
};


/**
 * @brief Cooley Turkey FFT
 * 
 * @tparam T Type of elements.
 * @param input Input data.
 * @param output Output data.
 */
template <typename T, std::size_t N = 16, std::size_t M = (1<<23), std::size_t P = 998244353, std::uint64_t G = 15311432, typename TTwiddleFactor = hls::fft::NTTTwiddleFactor<T, N, M, P, G> >
struct multiply_polynomial {
	static constexpr const std::size_t STAGES = hls::fft::clog2(N);

    typedef hls::fft::InterleavedArray<T, N, 1> ArrayType;
    NTTPolynomialRingFactor<T, N, P, G, false> phi;
    NTTPolynomialRingFactor<T, N, P, G, true> phi_inv;
    hls::fft::cooley_tukey_fft<T, N, TTwiddleFactor> fft_a;
    hls::fft::cooley_tukey_fft<T, N, TTwiddleFactor> fft_b;
    hls::fft::cooley_tukey_fft<T, N, TTwiddleFactor> ifft;
    
    void preprocess(const ArrayType& input, ArrayType& output)
    {
        for(std::size_t i = 0; i < N; i++) {
            output[i] = input[i] * phi[i];
        }
    }

    void multiply(const ArrayType& fft_a, const ArrayType& fft_b, ArrayType multiplied)
    {
        for(std::size_t i = 0; i < N; i++) {
            multiplied[i] = fft_a[i] * fft_b[i];
        }
    }
    void postprocess(const ArrayType& convoluted, ArrayType& output)
    {
        constexpr const auto POINTS_INVERSE = hls::fft::ensure_constexpr<typename T::value_type, T(N).pow(N - 2).value>::value;
        output[0] = (convoluted[0] * POINTS_INVERSE) * phi_inv[0];
        for(std::size_t i = 1; i < N; i++) {
            output[i] = (convoluted[N - (i - 1) - 1] * POINTS_INVERSE) * phi_inv[i];
        }
    }

	void run(const ArrayType& input_a, const ArrayType& input_b, ArrayType& output)
	{
		ArrayType input_conv_a, input_conv_b;
		ArrayType fft_a, fft_b;
		ArrayType multiplied;
		ArrayType convoluted;
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=input_conv_a factor=N
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=input_conv_b factor=N
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=multiplied factor=N
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=convoluted factor=N
#pragma HLS STABLE variable=phi
#pragma HLS BIND_STORAGE variable=phi.table type=rom_np
#pragma HLS STABLE variable=phi_inv
#pragma HLS BIND_STORAGE variable=phi_inv.table type=rom_np
#pragma HLS DATAFLOW
        // preprocess
        this->preprocess(input_a, input_conv_a);
        this->preprocess(input_b, input_conv_b);

        // FFT
        this->fft_a.run(input_conv_a, fft_a);
        this->fft_b.run(input_conv_b, fft_b);

        // multiply
        this->multiply(fft_a, fft_b, multiplied);

        // IFFT
        this->ifft.run(multiplied, convoluted);

        // postprocess
        this->postprocess(convoluted, output);
	}

	void run_pretransformed(const ArrayType& fft_a, const ArrayType& input_b, ArrayType& output)
	{
		ArrayType input_conv_b;
		ArrayType fft_b;
		ArrayType multiplied;
		ArrayType convoluted;
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=input_conv_b factor=N
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=multiplied factor=N
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=convoluted factor=N
#pragma HLS STABLE variable=phi
#pragma HLS BIND_STORAGE variable=phi.table type=rom_np
#pragma HLS STABLE variable=phi_inv
#pragma HLS BIND_STORAGE variable=phi_inv.table type=rom_np
#pragma HLS DATAFLOW
        // preprocess
        this->preprocess(input_b, input_conv_b);

        // FFT
        this->fft_b.run(input_conv_b, fft_b);

        // multiply
        this->multiply(fft_a, fft_b, multiplied);

        // IFFT
        this->ifft.run(multiplied, convoluted);

        // postprocess
        this->postprocess(convoluted, output);
	}
};

} // ntt_pr
