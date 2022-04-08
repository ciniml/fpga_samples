#include "fft.hpp"
#include "dj_fft.h"

#include <cstdint>
#include <cmath>
#include <iostream>

using namespace std;

int main(int argc, char* argv[])
{
    // TwiddleFactor<float, 16> w;
    // for(std::size_t i = 0; i < 16; i++) {
    //     cout << w[i] << ":" << TwiddleFactor<float, 16>::twiddle_factor(i) << ", ";
    // }
    // cout << endl;
    
    // BitReverse<16> bitrev;
    // for(std::size_t i = 0; i < 16; i++) {
    //     cout << bitrev[i] << ", ";
    // }
    // cout << endl;
    
    constexpr const std::size_t N = 16;

    InterleavedArray<std::complex<float>, N> input, output;
    std::vector<std::complex<float>> test_input, output_test;
    test_input.resize(N);
    for(std::size_t i = 0; i < N; i++) {
        auto v = sin(M_PI*2*i/N);
        input[i] = v / std::sqrt(N);
        test_input[i] = v;
    }
    for(std::size_t i = 0; i < N; i++) {
        cout << test_input[i] << " : " << input[i] << endl;
    }

    cooley_tukey_fft(input, output);
    output_test = dj::fft1d(test_input, dj::fft_dir::DIR_FWD);

    for(std::size_t i = 0; i < N; i++) {
        cout << std::norm(output_test[i]) << ":" << std::norm(output[i]) << endl;
    }
    cout << endl;
    return 0;
}