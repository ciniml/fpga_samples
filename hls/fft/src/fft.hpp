// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
#pragma once

#include <cstdint>
#include <cmath>
#include <array>
#ifdef __SYNTHESIS__
#include <ap_int.h>
#endif

namespace hls::fft {

/**
 * @brief An alternative of std::complex, which is difficult to use because its constructor initializes the value to zero. 
 *        The initialization causes extra WRITE operation, which requires additional port for RAM interface.
 * 
 * @tparam T A type to represent components of complex number. 
 */
template <typename T>
struct complex
{
    typedef T value_type;
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
    // Some std function overloads for hls::fft::complex.
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
 * @brief Calculate ceiling of logarithm of 2. (same as $clog2 in Verilog)
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
 * @brief Calculate number of trailing zeros.
 * 
 * @param n A number to calculate its number of trailing zeros.
 * @return constexpr std::size_t 
 */
static constexpr std::uint64_t ntz(std::uint64_t n)
{
    for(std::size_t count = 0; count < 64; count++) {
        if( (n&1) != 0 ) {
            return count;
        }
        n >>= 1;
    }
    return 64;
}

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

    InterleavedArray() = default;
    InterleavedArray(const T array[]) {
        for(std::size_t i = 0; i < WAY_SIZE; i++) {
            for(std::size_t w = 0; w < W; w++) {
                this->ways[w][i] = array[i*W + w];
            }
        }
    }
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
struct FFTTwiddleFactor
{
    static T twiddle_factor(std::size_t i) {
        auto t = 2*pi<typename T::value_type>()*i/N;
        auto cos = std::cos(t);
        auto sin = std::sin(t);
        return T(cos, sin);
    }
    static auto make_table()
    {
        std::array<T, N/4 + 1> table;
        for(std::size_t i = 0; i < N/4 + 1; i++ ) {
            table[i] = twiddle_factor(i);
        }
        return table;
    }

    std::array<T, N/4 + 1> table = make_table();
    
    T operator[](std::size_t i) const {
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
 * @brief A value of Galois Field GF(P) 
 * 
 * @tparam T Base type to represent GF(P) value.
 * @tparam P Prime number to construct galois field.
 */
template <typename T, std::uint64_t P = T(998244353)>
struct gf_value
{
    typedef gf_value<T, P> Self;
    T value;
    constexpr gf_value() {}   // DO NOT initialize anything not to generate extra WRITE operation in HLS synthesis.
    constexpr gf_value(const T& value) : value(value % P) {}
    
    constexpr Self reciprocal() const {
        // Calculate the receiprocal with extended euclidean algorithm.
        if( this->value == 1 ) return Self(1);
        T x = this->value;
        T y = P;
        T x_0 = 1;
        T y_0 = 0;
        while( y != 0 ) {
            auto q = x / y;
            auto r = x % y;
            auto next_x = y;
            auto next_y = r;
            x = next_x;
            y = next_y;

            auto next_x_0 = y_0;
            auto qq = T(q * y_0) % P;
            auto next_y_0 = x_0 < qq ? T((x_0 + P) - qq) : T(x_0 - qq);
            x_0 = next_x_0;
            y_0 = next_y_0;
        }
        return x == 1 ? Self(x_0) : Self(0);
    }

    // unary operators
    constexpr Self operator+() const { return *this; }
    constexpr Self operator-() const { return Self(P - this->value); }
    constexpr Self operator++() { return *this += Self(T(1)); }
    constexpr Self operator++(int) { auto result = *this; *this += Self(T(1)); return result; }
    constexpr Self operator--() { return *this -= Self(T(1)); }
    constexpr Self operator--(int) { auto result = *this; *this -= Self(T(1)); return result; }

    // assigning operators
    constexpr Self& operator+=(const Self& rhs) { 
        T new_value = this->value + rhs.value;
        this->value = new_value >= P ? T(new_value - P) : new_value;
        return *this;
    }
    constexpr Self& operator-=(const Self& rhs) { 
        this->value = this->value >= rhs.value ? T(this->value - rhs.value) : T(this->value + P - rhs.value);
        return *this;
    }
    constexpr Self& operator*=(const Self& rhs) { 
        this->value = (this->value * rhs.value) % P;
        return *this;
    }
    constexpr Self& operator/=(const Self& rhs) {
        auto reciprocal = rhs.reciprocal();
        *this *= reciprocal;
        return *this;
    }

    // binary operators
    constexpr Self operator+(const Self& rhs) const {
        Self new_value(*this);
        new_value += rhs;
        return new_value;
    }
    constexpr Self operator-(const Self& rhs) const {
        Self new_value(*this);
        new_value -= rhs;
        return new_value;
    }
    constexpr Self operator*(const Self& rhs) const {
        Self new_value(*this);
        new_value *= rhs;
        return new_value;
    }
    constexpr Self operator/(const Self& rhs) const {
        Self new_value(*this);
        new_value /= rhs;
        return new_value;
    }
    constexpr bool operator==(const Self& rhs) const { return this->value == rhs.value; }
    constexpr bool operator!=(const Self& rhs) const { return !(*this == rhs); }

    constexpr Self pow(const T& n) const {
        Self pow(1);
        Self value(this->value);
        T v(n);
        while( v > 0 ) {
            if( (v & 1) != 0 ) {
                pow *= value;
            }
            value *= value;
            v >>= 1;
        }
        return pow;
    }
    constexpr Self pow(const Self& n) const { return this->pow(n.value); }

    /**
     * @brief Calculate square root of this value by the Tonelli's algorithm.
     * 
     * @return Self 
     */
    constexpr Self sqrt() const {
        if( this->value == T(0) ) return Self(T(0));
        if( this->value == T(1) ) return Self(T(1));

        // First, find m and a where 2^m * a + 1 = P
        // m is the number of trailing zeros of (P - 1)
        auto m = ntz(P - 1);
        auto m_2 = (1u << m);   // 2^m
        auto a = Self(P - 1) / Self(m_2);

        // Find non-squared number
        Self b(1);
        while( b.pow( (P - 1) / 2 ) != Self(P - 1) ) {
            ++b;
        }
        auto c = b.pow(a);
        auto inv = this->reciprocal();
        auto r = this->pow((a.value + 1)/2);

        m_2 >>= 2;
        for( T i = 1; i < m; i++, m_2 >>= 1 ) {
            auto d = (r * r * inv).pow(m_2);
            if( d.value != 1 ) {
                r *= c;
            }
            c *= c;
        }
        return r;
    }
};

/**
 * @brief Twiddle factor for number theorem transform (NTT) on GF(P)
 * 
 * @tparam T Type to represent GF(P) value. Usually it is gf_value<T>
 * @tparam N Number of FFT points.
 * @tparam P A prime number
 * @tparam G The base root of the prime root.
 * @tparam A The power factor of the prime root. G^A is used as the prime root of this twiddle factor.
 */

template <typename T, std::size_t N, std::size_t M = (1<<23), std::uint64_t P = 998244353, std::uint64_t G = 15311432>
struct NTTTwiddleFactor
{
    static constexpr auto make_table()
    {
        std::array<T, N> table;
        auto log2_N = clog2(N);
        auto log2_M = clog2(M);
        auto g = T(G);
        for(std::size_t i = 0; i < log2_M - log2_N; i++) {
            g *= g;
        }
        auto g_i = T(1);
        for(std::size_t i = 0; i < N; i++, g_i *= g ) {
            table[i] = g_i;
        }
        return table;
    }

    std::array<T, N> table = make_table();
    
    T operator[](std::size_t i) const {
        return this->table[i];
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
	static constexpr const std::size_t NUMBER_OF_BITS = clog2(N);
#ifndef __SYNTHESIS__
    static constexpr std::size_t bit_reverse(std::size_t i) {
        auto number_of_bits = NUMBER_OF_BITS;
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
#else
    // Use bit reverse operation of ap_uint instead when synthesize.
    std::size_t operator[](std::size_t i) const {
    	auto bits = ap_uint<NUMBER_OF_BITS>(i);
    	return bits.range(0, NUMBER_OF_BITS-1);
    }
#endif
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
template <typename T, std::size_t N, typename TTwiddleFactor = FFTTwiddleFactor<T, N>>
static void cooley_tukey_fft_stage(const std::size_t stage, const InterleavedArray<T, N, 1>& input, InterleavedArray<T, N, 1>& output, const TTwiddleFactor& w)
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
template <typename T, std::size_t N = 16, typename TTwiddleFactor = FFTTwiddleFactor<T, N>>
struct cooley_tukey_fft {
	static constexpr const std::size_t STAGES = clog2(N);
	TTwiddleFactor w;
	BitReverse<N> bitrev;

	void run(const InterleavedArray<T, N, 1>& input, InterleavedArray<T, N, 1>& output)
	{
		InterleavedArray<T, N, 1> stage_in[STAGES];
#pragma HLS ARRAY_PARTITION dim=1 type=block variable=stage_in factor=STAGES
#pragma HLS BIND_STORAGE variable=stage_in type=ram_s2p impl=uram
#pragma HLS STABLE variable=w
#pragma HLS BIND_STORAGE variable=w.table type=rom_np

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

template <typename T, T P>
static std::ostream& operator<<(std::ostream& self, const hls::fft::gf_value<T, P>& c) {
    return self << c.value;
}

} // std
#endif
