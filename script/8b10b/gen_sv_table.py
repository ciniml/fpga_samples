import io
import math
import table

def clog2(x: int) -> int:
    return int(math.ceil(math.log2(x)))

def gen_sv_table_function(table: dict, name: str, writer: io.TextIOBase):
    keys = table.keys()
    sorted_keys = sorted(keys)
    max_8bit_value = max([x['8bit'] for x in table.values()])
    address_bits = clog2(max_8bit_value * 2)
    address_hex_digits = (address_bits + 3) // 4
    address_type = f"logic [{address_bits - 1}:0]"
    output_type = "logic [9:0]"
    writer.write(f'function automatic {output_type} {name}(input {address_type} address);\n')
    writer.write('case(address)\n')
    for key in sorted_keys:
        row = table[key]
        value = row['8bit']
        address = value * 2 # lower: disparity minus, upper: disparity plus
        rd_minus = row['10bit_rd_minus']
        rd_plus = row['10bit_rd_plus']
        writer.write(f'{address_bits}\'h{(address + 0):0{address_hex_digits}x}: return 10\'b{rd_minus:010b}; //{key} RD-\n')
        writer.write(f'{address_bits}\'h{(address + 1):0{address_hex_digits}x}: return 10\'b{rd_plus:010b}; //{key} RD+\n')
    writer.write('endcase\n')
    writer.write('endfunction\n')

def gen_sv_table_rom(table: dict, name: str, writer: io.TextIOBase):
    keys = table.keys()
    sorted_keys = sorted(keys)
    max_8bit_value = max([x['8bit'] for x in table.values()])
    address_bits = clog2(max_8bit_value * 2)
    address_hex_digits = (address_bits + 3) // 4
    address_type = f"logic [{address_bits - 1}:0]"
    output_type = "logic [9:0]"
    writer.write(f'{output_type} {name}[0:{address_bits-1}];\n')
    writer.write('initial begin\n')
    for key in sorted_keys:
        row = table[key]
        value = row['8bit']
        address = value * 2 # lower: disparity minus, upper: disparity plus
        rd_minus = row['10bit_rd_minus']
        rd_plus = row['10bit_rd_plus']
        writer.write(f'{name}[{address_bits}\'h{(address + 0):0{address_hex_digits}x}] = 10\'b{rd_minus:010b}; //{key} RD-;\n')
        writer.write(f'{name}[{address_bits}\'h{(address + 1):0{address_hex_digits}x}] = 10\'b{rd_plus:010b}; //{key} RD+;\n')
    writer.write('end\n')

with open('8b10b_table.sv', 'w') as f:
    gen_sv_table_function(table.k_table, 'k_table', f)
    gen_sv_table_rom(table.d_table, 'd_table', f)