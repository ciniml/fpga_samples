// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
#pragma once

#include <cstdint>
#include <cmath>
#include <array>

namespace hls::fft {
template <typename T>
struct complex
{
    typedef complex<T> Self;
    T real;
    T imag;

    constexpr complex() {}
    constexpr complex(const T& real) : real(real), imag(0) {}
    constexpr complex(const T& real, const T& imag) : real(real), imag(imag) {}

    constexpr Self conjugate() const { 
        return Self(this->real, -this->imag);
    }
    constexpr T abs_squared() const {
        return this->real*this->real + this->imag*this->imag;
    }
    T abs() const {
        return std::sqrt(this->abs_squared());
    }
    T arg() const {
        return std::atan2(this->imag, this->real);
    }

    // unary operator
    constexpr Self operator+() const {
        return *this;
    }
    constexpr Self operator-() const {
        return Self(-this->real, -this->imag);
    }

    // complex - real operations
    constexpr Self& operator*=(const T& rhs) {
        this->real *= rhs;
        this->imag *= rhs;
        return *this;
    }
    constexpr Self& operator/=(const T& rhs) {
        this->real /= rhs;
        this->imag /= rhs;
        return *this;
    }
    constexpr Self operator*(const T& rhs) const {
        return Self(this->real*rhs, this->imag*rhs);
    }
    constexpr Self operator/(const T& rhs) const {
        return Self(this->real/rhs, this->imag/rhs);
    }

    // complex - complex operations
    constexpr Self& operator+=(const Self& rhs) {
        this->real += rhs.real;
        this->imag += rhs.imag;
        return *this;
    }
    constexpr Self& operator-=(const Self& rhs) {
        this->real -= rhs.real;
        this->imag -= rhs.imag;
        return *this;
    }
    constexpr Self& operator*=(const Self& rhs) {
        auto real = this->real*rhs.real - this->imag*rhs.imag;
        auto imag = this->real*rhs.imag + this->imag*rhs.real;
        this->real = real;
        this->imag = imag;
        return *this;
    }
    constexpr Self& operator/=(const Self& rhs) {
        auto reciprocal = rhs.real*rhs.real + rhs.imag*rhs.imag;
        auto real = (this->real*rhs.real + this->imag*rhs.imag)/reciprocal;
        auto imag = (this->imag*rhs.real - this->real*rhs.imag)/reciprocal;
        this->real = real;
        this->imag = imag;
        return *this;
    }
    constexpr Self operator+(const Self& rhs) const {
        return Self(this->real + rhs.real, this->imag + rhs.imag);
    }
    constexpr Self operator-(const Self& rhs) const {
        return Self(this->real - rhs.real, this->imag - rhs.imag);
    }
    constexpr Self operator*(const Self& rhs) const {
        return Self(this->real*rhs.real - this->imag*rhs.imag, this->real*rhs.imag + this->imag*rhs.real);
    }
    constexpr Self operator/(const Self& rhs) const {
        auto reciprocal = rhs.real*rhs.real + rhs.imag*rhs.imag;
        return Self((this->real*rhs.real + this->imag*rhs.imag)/reciprocal, (this->imag*rhs.real - this->real*rhs.imag)/reciprocal);
    }
};

} // hls::fft

namespace std {
    template<typename T>
    constexpr static T real(const hls::fft::complex<T>& c) { return c.real; }
    template<typename T>
    constexpr static T imag(const hls::fft::complex<T>& c) { return c.imag; }
    template<typename T>
    constexpr static hls::fft::complex<T> conj(const hls::fft::complex<T>& c) { return c.conjugate(); }
    template<typename T>
    static T norm(const hls::fft::complex<T>& c) { return c.abs_squared(); }
    template<typename T>
    static T abs(const hls::fft::complex<T>& c) { return c.abs(); }
}

namespace hls::fft {
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
    T ways[W][WAY_SIZE];

    InterleavedArray() {}
    T& operator[](std::size_t i) { 
        return this->ways[i%W][i/W]; 
    }
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
    typedef complex<T> complex_type;
    
    static complex_type twiddle_factor(std::size_t i) {
        auto t = 2*pi<T>()*i/N;
        T cos = std::cos(t);
        T sin = std::sin(t);
        return complex_type(cos, sin);
    }
    static auto make_table()
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
 * @brief Calculated ceiling of logarithm of 2. (same as $clog2 in Verilog)
 * 
 * @param n A number to calculate its ceiling of logarithm of 2.
 * @return constexpr std::size_t 
 */
static constexpr std::size_t clog2(std::size_t n)
{
    std::size_t count = 0;
    while((n >>= 1) != 0) {
        count++;
    }
    return count;
}

/**
 * @brief Bit reversal table.
 * 
 * @tparam N Number of bits.
 */
template <std::size_t N>
struct BitReverse
{
    static constexpr std::size_t bit_reverse(std::size_t i) {
        auto number_of_bits = static_cast<std::size_t>(clog2(N));
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
static void cooley_tukey_fft_stage(const std::size_t stage, const InterleavedArray<complex<T>, N, 1>& input, InterleavedArray<complex<T>, N, 1>& output, const TwiddleFactor<T, N>& w)
{
    const std::size_t block_size = 1<<(stage+1);
    for(std::size_t block = 0; block < N / block_size; block++ ) {
        for(std::size_t i = 0; i < block_size / 2; i++) {
#pragma HLS PIPELINE II=2
            auto block_offset = block_size*block;
            auto index_0 = block_offset + i;
            auto index_1 = block_offset + i + block_size/2;

            auto a = input[index_0];
            auto b = input[index_1] * w[i*N/block_size];
            output[index_0] = a + b;
            output[index_1] = a - b;
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
struct cooley_tukey_fft {
	static constexpr const std::size_t STAGES = clog2(N);
	TwiddleFactor<T, N> w;
	BitReverse<N> bitrev;

	void run(const InterleavedArray<complex<T>, N, 1>& input, InterleavedArray<complex<T>, N, 1>& output)
	{
		InterleavedArray<complex<T>, N, 1> stage_in[STAGES];
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=stage_in factor=STAGES
#pragma HLS STABLE variable=w
#pragma HLS BIND_STORAGE variable=w.table type=rom_np
#pragma HLS STABLE variable=bitrev
#pragma HLS BIND_STORAGE variable=bitrev.table type=rom_1p

		for(std::size_t i = 0; i < N; i++ ) {
			stage_in[0][i] = input[bitrev[i]];
		}
		for( std::size_t stage = 0; stage < STAGES - 1; stage++) {
#pragma HLS UNROLL factor=N
			cooley_tukey_fft_stage<T, N>(stage, stage_in[stage], stage_in[stage + 1], w);
		}
		cooley_tukey_fft_stage<T, N>(STAGES-1, stage_in[STAGES-1], output, w);
	}
};

} // hls::fft


#ifndef __SYNTHESIS__
#include <iostream>
namespace std  {

template <typename T>
static std::ostream& operator<<(std::ostream& self, const hls::fft::complex<T>& c) {
    return self << "(" << c.real << "," << c.imag << ")";
}

} // std
#endif
