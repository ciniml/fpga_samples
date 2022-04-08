import numpy as np
import numpy.fft as fft
import cmath

input = [cmath.sin(cmath.pi*2*x/16) + 1 for x in range(16)]
output = np.abs(fft.fft(input))

print(output)