#include <stdint.h>

void __attribute__((naked)) __attribute__((section(".isr_vector"))) isr_vector(void)
{
    asm volatile ("j start");
    asm volatile ("j start");
}

void __attribute__((noreturn)) main(void);
extern uint32_t _bss_start;
extern uint32_t _bss_end;
extern uint32_t _data_start;
extern uint32_t _data_end;
extern uint32_t _data_rom_start;
void init(void)
{
    uint32_t* bss_end = &_bss_end; 
    for(volatile uint32_t* bss = &_bss_start; bss < bss_end; bss++) {
        *bss = 0;
    }
    uint32_t* data_end = &_data_end; 
    volatile uint32_t* data_rom = &_data_rom_start; 
    for(volatile uint32_t* data = &_data_start; data < data_end; data++, data_rom++) {
        *data = *data_rom;
    }
}

extern void __attribute__((naked)) start(void)
{
    asm volatile ("la sp, ramend");
    asm volatile ("addi sp, sp, -4");
    init();
    main();
}

static volatile uint32_t* const REG_ID           = (volatile uint32_t*)(0x40000000 + 0x00*4);
static volatile uint32_t* const REG_CLOCK_HZ     = (volatile uint32_t*)(0x40000000 + 0x01*4);
static volatile uint32_t* const REG_OUT          = (volatile uint32_t*)(0x40000000 + 0x02*4);
static volatile uint32_t* const REG_SERIAL_OUT   = (volatile uint32_t*)(0x40000000 + 0x03*4);

static void putc(char c)
{
    while(*REG_SERIAL_OUT & 0x100);
    *REG_SERIAL_OUT = c;
}
static void puts(const char* s)
{
    while(*s) {
        putc(*s++);
    }
}

static uint64_t read_cycle(void)
{
    uint32_t l, h, hv;
    do {
        asm volatile ("rdcycleh %0" : "=r" (h));
        asm volatile ("rdcycle  %0" : "=r" (l));
        asm volatile ("rdcycleh %0" : "=r" (hv));
    } while(h != hv);
    return ((uint64_t)h << 32) | l;
} 

void __attribute__((noreturn)) main(void)
{
    uint32_t led_out = 1;
    uint32_t pattern_index = 0;
    const uint32_t clock_hz = *REG_CLOCK_HZ;
    while(1) {
        // *REG_OUT = led_out;
        // uint64_t start = read_cycle();
        // while(read_cycle() - start < clock_hz/10);
        // led_out = (led_out << 1) | ((led_out >> 31) & 1);
        puts("Hello, World!\n");
    }
}