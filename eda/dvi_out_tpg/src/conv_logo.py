#!/usr/bin/env python3

from typing import Tuple
from PIL import Image
from PIL import GifImagePlugin

img = Image.open('./interface_logo.png')
#img = img.convert('RGB')
print(f"{img.size} {img.format} {img.mode} {img.getpixel((0,0))}")

stride = (img.size[0] + 7) & ~7

def is_black(pixel: Tuple[int, int, int]) -> bool:
    return pixel[0] + pixel[1] + pixel[2] < 128*3
def is_transparent(pixel: Tuple[int, int, int, int]) -> bool:
    return pixel[3] < 128

def bit_reverse(b:int) -> int:
    r = 0
    for i in range(8):
        r <<= 1
        r |= b & 1
        b >>= 1
    return r

image_bytes = stride * img.size[1]
buffer = bytearray(image_bytes)
ptr = memoryview(buffer)

for y in range(img.size[1]):
    pixels = 0
    for x in range(img.size[0]):
        if x > 0 and (x & 7) == 0:
            ptr[0] = pixels
            ptr = ptr[1:]
            pixels = 0
        pixels >>= 1
        #pixels |= 128 if ((x & 1) | (y & 1)) else 0
        #pixels |= 0 if not is_black(img.getpixel((x, y))) else 128
        pixels |= 0 if is_transparent(img.getpixel((x, y))) else 128
        
    if (img.size[0] & 7) != 0:
        ptr[0] = pixels >> (8 - (img.size[0] & 7))
        ptr = ptr[1:]

with open('interface_logo.hex', "w") as f:
    for b in buffer:
        print(f"{b:02X}", file=f)
with open('interface_logo.bin', "wb") as f:
    for i in range(len(buffer)):
        buffer[i] = bit_reverse(buffer[i])
    f.write(buffer)
        
