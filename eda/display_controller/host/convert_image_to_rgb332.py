#!/usr/bin/env python3
"""
Image to RGB332 Converter

Converts fuga_300px.png to height 90px and RGB332 format binary output.
RGB332 format: 3bit Red + 3bit Green + 2bit Blue = 8bit per pixel
"""

from PIL import Image
import struct
import os

def rgb_to_rgb332(r, g, b):
    """
    Convert RGB888 to RGB332 format

    Args:
        r, g, b: RGB values (0-255)

    Returns:
        Single byte in RGB332 format
    """
    # Extract upper bits: R(3), G(3), B(2)
    r3 = (r >> 5) & 0x07  # Upper 3 bits of red
    g3 = (g >> 5) & 0x07  # Upper 3 bits of green
    b2 = (b >> 6) & 0x03  # Upper 2 bits of blue

    # Pack into single byte: [R2 R1 R0 G2 G1 G0 B1 B0]
    rgb332 = (r3 << 5) | (g3 << 2) | b2
    return rgb332

def convert_image():
    """
    Main conversion function
    """
    # Input and output file paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, "fuga_300px.png")
    output_file = os.path.join(script_dir, "fuga_300px_90h_rgb332.bin")

    try:
        # Load image
        print(f"Loading image: {input_file}")
        img = Image.open(input_file)
        print(f"Original size: {img.size[0]}x{img.size[1]}")

        # Convert to RGB if not already
        if img.mode != 'RGB':
            img = img.convert('RGB')
            print(f"Converted to RGB mode")

        # Calculate new width maintaining aspect ratio
        original_width, original_height = img.size
        target_height = 90
        aspect_ratio = original_width / original_height
        target_width = int(target_height * aspect_ratio)

        print(f"Resizing to: {target_width}x{target_height}")

        # Resize image using high-quality resampling
        img_resized = img.resize((target_width, target_height), Image.Resampling.LANCZOS)

        # Convert to RGB332 and write binary data
        print(f"Converting to RGB332 format...")

        with open(output_file, 'wb') as f:
            pixel_count = 0
            for y in range(target_height):
                for x in range(target_width):
                    r, g, b = img_resized.getpixel((x, y))
                    rgb332_byte = rgb_to_rgb332(r, g, b)
                    f.write(struct.pack('B', rgb332_byte))
                    pixel_count += 1

        print(f"Conversion completed!")
        print(f"Output file: {output_file}")
        print(f"Final dimensions: {target_width}x{target_height}")
        print(f"Total pixels: {pixel_count}")
        print(f"File size: {pixel_count} bytes")

        # Create a text file with image info for reference
        info_file = os.path.join(script_dir, "fuga_300px_90h_rgb332.txt")
        with open(info_file, 'w') as f:
            f.write(f"Image: fuga_300px.png\n")
            f.write(f"Original size: {original_width}x{original_height}\n")
            f.write(f"Converted size: {target_width}x{target_height}\n")
            f.write(f"Format: RGB332 (3+3+2 bits)\n")
            f.write(f"File size: {pixel_count} bytes\n")
            f.write(f"Binary file: fuga_300px_90h_rgb332.bin\n")

        print(f"Info file created: {info_file}")

    except FileNotFoundError:
        print(f"Error: Input file not found: {input_file}")
        print("Please ensure fuga_300px.png exists in the same directory as this script.")
    except Exception as e:
        print(f"Error during conversion: {e}")

def test_rgb332_conversion():
    """
    Test RGB332 conversion with sample values
    """
    print("\nTesting RGB332 conversion:")
    test_colors = [
        (255, 255, 255),  # White
        (255, 0, 0),      # Red
        (0, 255, 0),      # Green
        (0, 0, 255),      # Blue
        (0, 0, 0),        # Black
        (128, 128, 128),  # Gray
    ]

    for r, g, b in test_colors:
        rgb332 = rgb_to_rgb332(r, g, b)
        print(f"RGB({r:3d},{g:3d},{b:3d}) -> RGB332: 0x{rgb332:02X} ({rgb332:08b})")

if __name__ == "__main__":
    print("Image to RGB332 Converter")
    print("=" * 40)

    # Run conversion
    convert_image()

    # Run test
    test_rgb332_conversion()