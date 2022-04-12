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
        auto phi = T(G).sqrt();
        if( INVERSE ) {
            phi = phi.reciprocal();
        }
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
    static constexpr const auto POINTS_INVERSE = T(N).pow(N - 2);

    typedef hls::fft::InterleavedArray<T, N, 1> ArrayType;
    TTwiddleFactor w;
    NTTPolynomialRingFactor<T, N, P, G, false> phi;
    NTTPolynomialRingFactor<T, N, P, G, true> phi_inv;
    hls::fft::cooley_tukey_fft<T, N, TTwiddleFactor> fft_a;
    hls::fft::cooley_tukey_fft<T, N, TTwiddleFactor> fft_b;
    hls::fft::cooley_tukey_fft<T, N, TTwiddleFactor> ifft;
    
	void run(const ArrayType& input_a, const ArrayType& input_b, ArrayType& output)
	{
		ArrayType input_conv_a, input_conv_b;
		ArrayType fft_a, fft_b;
		ArrayType multiplied;
		ArrayType convoluted;
#pragma HLS STABLE variable=w
#pragma HLS BIND_STORAGE variable=w.table type=rom_np
#pragma HLS STABLE variable=phi
#pragma HLS BIND_STORAGE variable=phi.table type=rom_np
#pragma HLS STABLE variable=phi_inv
#pragma HLS BIND_STORAGE variable=phi_inv.table type=rom_np

        // preprocess
        for(std::size_t i = 0; i < N; i++) {
            input_conv_a[i] = input_a[i] * phi[i];
            input_conv_b[i] = input_b[i] * phi[i];
        }
        // FFT
        this->fft_a.run(input_conv_a, fft_a);
        this->fft_a.run(input_conv_b, fft_b);
// #ifndef __SYNTHESIS__
//         for(std::size_t i = 0; i < N; i++) {
//             std::cout << fft_b[i] << ", ";
//         }
//         std::cout << std::endl;
// #endif
        // multiply
        for(std::size_t i = 0; i < N; i++) {
            multiplied[i] = fft_a[i] * fft_b[i];
        }
#ifndef __SYNTHESIS__
        for(std::size_t i = 0; i < N; i++) {
            std::cout << multiplied[i] << ", ";
        }
        std::cout << std::endl;
#endif
        // IFFT
        this->ifft.run(multiplied, convoluted);
#ifndef __SYNTHESIS__
        for(std::size_t i = 0; i < N; i++) {
            std::cout << convoluted[i] << ", ";
        }
        std::cout << std::endl;
#endif
#ifndef __SYNTHESIS__
        std::cout << convoluted[0] * POINTS_INVERSE << ", ";
        for(std::size_t i = 1; i < N; i++) {
            std::cout <<  (convoluted[N - (i - 1) - 1] * POINTS_INVERSE) << ", ";
        }
        std::cout << std::endl;
#endif
        // postprocess
        output[0] = (convoluted[0] * POINTS_INVERSE) * phi_inv[0];
        for(std::size_t i = 1; i < N; i++) {
            output[i] = (convoluted[N - (i - 1) - 1] * POINTS_INVERSE) * phi_inv[i];
        }
	}
};

} // ntt_pr
