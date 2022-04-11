// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

#include "fft.hpp"
#include "ntt_pr.hpp"
#include <cstdint>
#include <cmath>
#include <iostream>
#include <complex>

using namespace std;
using namespace hls::fft;
using namespace hls::ntt_pr;

static constexpr const std::uint64_t P = 337;
static constexpr const std::uint64_t G = 85;
static constexpr const std::size_t N = 8;
static constexpr const std::size_t M = 8;
typedef gf_value<std::uint64_t, P> Element;
typedef NTTTwiddleFactor<Element, N, M, P, G> TwiddleFactor;

int main(int argc, char* argv[])
{
    TwiddleFactor w;
    for(std::size_t i = 0; i < N; i++) {
        cout << w[i].value << ", ";
    }
    cout << endl;

    Element input_elements_a[] = {19,  112, 123,  72, 283, 335, 180, 334};
    Element input_elements_b[] = {272, 191,  83, 127,  76, 135, 304, 325};
    InterleavedArray<Element, N> input_a(input_elements_a);
    InterleavedArray<Element, N> input_b(input_elements_b);
    InterleavedArray<Element, N> output;

    // for(std::uint64_t i = 1; i < P; i++ ) {
    //     auto v = Element(i);
    //     auto r = v.reciprocal();
    //     auto a = v*r;
    //     cout << v.value << "," << r.value << "," << a.value << endl;
    //     if( r != Element(0) && a != Element(1) ) {
    //         cerr << "reciprocal wrong" << endl;
    //         return 1;
    //     }
    // }

    // auto phi = Element(G).sqrt();
    // cout << "phi: " << phi.value << endl;
    // auto phi_2 = phi.pow(2);
    // cout << "phi^2: " << phi_2.value << " == " << G << endl;
    // if( phi_2 != Element(G) ) {
    //     cerr << "sqrt is wrong." << endl;
    //     return 1;
    // }
    // Element phi_n(1);

    // for(std::size_t i = 0; i < N; i++) {
    //     input_a[i] *= phi_n;
    //     input_b[i] *= phi_n;
    //     phi_n *= Element(phi);
    // }

    // cooley_tukey_fft<Element, N, TwiddleFactor> fft;
    // fft.run(input_a, output);
    
    // for(std::size_t i = 0; i < N; i++) {
    //     cout << output[i].value << endl;
    // }
    // cout << endl;

    multiply_polynomial<Element, N, M, P, G, TwiddleFactor> mp;
    mp.run(input_a, input_b, output);
    for(std::size_t i = 0; i < N; i++) {
        cout << output[i].value << ", ";
    }
    cout << endl;

    return 0;
}