// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
#pragma once

#include <cstdint>
#include <cmath>
#include <array>
#include <complex>

#include <gcem.hpp>

/**
 * @brief W-way interleaving array.
 * 
 * @tparam T Type of element.
 * @tparam N Number of items in this array.
 * @tparam W Number of interleave ways.
 */
template<typename T, std::size_t N, std::size_t W = 1> 
struct InterleavedArray
{
    static constexpr const std::size_t WAY_SIZE = N/W;
    std::array<T, WAY_SIZE> ways[W];

    T& operator[](std::size_t i) { return this->ways[i%W][i/W]; }
    const T& operator[](std::size_t i) const { return this->ways[i%W][i/W]; }
};

/**
 * @brief returns π in the type T
 * 
 * @tparam T Type of the return value which represents π.
 * @return constexpr T π as the type T.
 */
template <typename T>
static constexpr T pi() { return T(M_PI); }

/**
 * @brief Radix-2 FFT twiddle factor table.
 * 
 * @tparam T Type of elements of this table.
 * @tparam N Number of elements in this table.
 */
template <typename T, std::size_t N>
struct TwiddleFactor
{
    typedef std::complex<T> complex_type;
    
    static constexpr complex_type twiddle_factor(std::size_t i) {
        auto t = 2*pi<T>()*i/N;
        T cos = gcem::cos(t);
        T sin = gcem::sin(t);
        return complex_type(cos, sin);
    }
    static constexpr auto make_table()
    {
        std::array<complex_type, N/4 + 1> table;
        for(std::size_t i = 0; i < N/4 + 1; i++ ) {
            table[i] = twiddle_factor(i);
        }
        return table;
    }

    std::array<complex_type, N/4 + 1> table = make_table();
    
    complex_type operator[](std::size_t i) const {
        auto i_mod_N = i % N;
        if( i_mod_N < N*1/4 ) {
            return this->table[i];
        } else if( i_mod_N < N*2/4 ) {
            return -std::conj(this->table[N*2/4 - i_mod_N]);
        } else if( i_mod_N < N*3/4 ) {
            return -this->table[i_mod_N - N*2/4];
        } else {
            return std::conj(this->table[N - i_mod_N]);
        }
    }
};

/**
 * @brief Bit reversal table.
 * 
 * @tparam N Number of bits.
 */
template <std::size_t N>
struct BitReverse
{
    static constexpr std::size_t bit_reverse(std::size_t i) {
        auto number_of_bits = static_cast<std::size_t>(gcem::log2(N));
        std::size_t forward_mask = 1;
        std::size_t reverse_mask = 1 << (number_of_bits - 1);
        for(std::size_t bit_index = 0; bit_index < number_of_bits/2; bit_index++, forward_mask <<= 1, reverse_mask >>= 1) {
            std::size_t t = i & reverse_mask;
            if( (i & forward_mask) != 0 ) {
                i |= reverse_mask;
            } else {
                i &= ~reverse_mask;
            }
            if( t != 0 ) {
                i |= forward_mask;
            } else {
                i &= ~forward_mask;
            }
        }
        return i;
    }
    static constexpr auto make_table()
    {
        std::array<std::size_t, N> table;
        for(std::size_t i = 0; i < N; i++ ) {
            table[i] = bit_reverse(i);
        }
        return table;
    }

    std::array<std::size_t, N> table = make_table();
    
    std::size_t operator[](std::size_t i) const {
        return this->table[i];
    }
};

/**
 * @brief Calculate a stage of Cooley-Tukey FFT.
 * 
 * @tparam T Type of elements.
 * @tparam N Number of FFT points.
 * @param stage stage number.
 * @param input Input data of this stage.
 * @param output Output data of this stage.
 * @param w Twiddle factor table.
 */
template <typename T, std::size_t N>
static void cooley_tukey_fft_stage(const std::size_t stage, const InterleavedArray<std::complex<T>, N, 1>& input, InterleavedArray<std::complex<T>, N, 1>& output, const TwiddleFactor<T, N>& w)
{
    const std::size_t block_size = 1<<(stage+1);
    for(std::size_t block = 0; block < N / block_size; block++ ) {
        for(std::size_t i = 0; i < block_size / 2; i++) {
            auto block_offset = block_size*block;
            auto a = input[block_offset + i];
            auto b = input[block_offset + i + block_size/2] * w[i*N/block_size];
            output[block_offset + i] = a + b;
            output[block_offset + i + block_size/2] = a - b;
        }
    }
}

/**
 * @brief Cooley Turkey FFT
 * 
 * @tparam T Type of elements.
 * @param input Input data.
 * @param output Output data.
 */
template <typename T, std::size_t N = 16>
static void cooley_tukey_fft(const InterleavedArray<std::complex<T>, N, 1>& input, InterleavedArray<std::complex<T>, N, 1>& output)
{
    constexpr const std::size_t STAGES = gcem::log2(N);

    TwiddleFactor<T, N> w;
    BitReverse<N> bitrev;
    InterleavedArray<std::complex<T>, N, 1> stage_in[STAGES];
    for(std::size_t i = 0; i < N; i++ ) {
        stage_in[0][i] = input[bitrev[i]];
    }
    for( std::size_t stage = 0; stage < STAGES - 1; stage++) {
        cooley_tukey_fft_stage<T, N>(stage, stage_in[stage], stage_in[stage + 1], w);
    }
    cooley_tukey_fft_stage<T, N>(STAGES-1, stage_in[STAGES-1], output, w);
}