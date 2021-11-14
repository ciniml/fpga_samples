#include <stdint.h>

void __attribute__((naked)) __attribute__((section(".isr_vector"))) isr_vector(void)
{
    asm volatile ("j start");
    asm volatile ("j start");
}

void __attribute__((noreturn)) main(void);

void __attribute__((naked)) start(void)
{
    asm volatile ("la sp, ramend");
    main();
}

static volatile uint32_t* const REG_ID           = (volatile uint32_t*)(0x30000000 + 0x00*4);
static volatile uint32_t* const REG_LED          = (volatile uint32_t*)(0x30000000 + 0x01*4);
static volatile uint32_t* const REG_KEY          = (volatile uint32_t*)(0x30000000 + 0x02*4);
static volatile uint32_t* const REG_SWITCH       = (volatile uint32_t*)(0x30000000 + 0x03*4);
static volatile uint32_t* const REG_COLOR_LED_0  = (volatile uint32_t*)(0x30000000 + 0x04*4);
static volatile uint32_t* const REG_COLOR_LED_1  = (volatile uint32_t*)(0x30000000 + 0x05*4);
static volatile uint32_t* const REG_COLOR_LED_2  = (volatile uint32_t*)(0x30000000 + 0x06*4);
static volatile uint32_t* const REG_COLOR_LED_3  = (volatile uint32_t*)(0x30000000 + 0x07*4);
static volatile uint32_t* const REG_SEG_LED_0    = (volatile uint32_t*)(0x30000000 + 0x08*4);
static volatile uint32_t* const REG_SEG_LED_1    = (volatile uint32_t*)(0x30000000 + 0x09*4);
static volatile uint32_t* const REG_SEG_LED_2    = (volatile uint32_t*)(0x30000000 + 0x0a*4);
static volatile uint32_t* const REG_SEG_LED_3    = (volatile uint32_t*)(0x30000000 + 0x0b*4);
static volatile uint32_t* const REG_CLOCK_HZ     = (volatile uint32_t*)(0x30000000 + 0x0c*4);
static volatile uint32_t* const REG_UART_STATUS  = (volatile uint32_t*)(0x30000000 + 0x0d*4);
static volatile uint32_t* const REG_UART_DATA    = (volatile uint32_t*)(0x30000000 + 0x0e*4);

static const uint32_t BIT_KEY_1 = (1u << 0);
static const uint32_t BIT_KEY_2 = (1u << 0);
static const uint32_t BIT_KEY_3 = (1u << 0);
static const uint32_t BIT_KEY_4 = (1u << 0);
static const uint32_t BIT_KEY_5 = (1u << 0);
static const uint32_t BIT_KEY_6 = (1u << 0);
static const uint32_t BIT_KEY_7 = (1u << 0);
static const uint32_t BIT_KEY_8 = (1u << 0);

static const uint32_t BIT_SW_1 = (1u << 0);
static const uint32_t BIT_SW_2 = (1u << 0);
static const uint32_t BIT_SW_3 = (1u << 0);
static const uint32_t BIT_SW_4 = (1u << 0);
static const uint32_t BIT_SW_5 = (1u << 0);
static const uint32_t BIT_SW_6 = (1u << 0);
static const uint32_t BIT_SW_7 = (1u << 0);
static const uint32_t BIT_SW_8 = (1u << 0);

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

static void uart_tx(uint8_t value) 
{
    while((*REG_UART_STATUS & 0b01) == 0);
    *REG_UART_DATA = value;
}
static uint8_t uart_rx() 
{
    while((*REG_UART_STATUS & 0b10) == 0);
    return *REG_UART_DATA;
}

void __attribute__((noreturn)) main(void)
{
    uint32_t led_out = 1;
    const uint32_t clock_hz = *REG_CLOCK_HZ;
    while(1) {
        *REG_LED = led_out;
        led_out = (led_out << 1) | ((led_out >> 7) & 1);
        uint64_t start = read_cycle();
        while(read_cycle() - start < clock_hz) {
            *REG_COLOR_LED_0 = (*REG_KEY & 0x7);
            *REG_SEG_LED_3 = 0x20 | ((start >> 16) & 0x0f);
            *REG_SEG_LED_2 = 0x20 | ((start >> 20) & 0x0f);
            *REG_SEG_LED_1 = 0x20 | ((start >> 24) & 0x0f);
            *REG_SEG_LED_0 = 0x20 | ((start >> 28) & 0x0f);
        }
        
        if( *REG_KEY & BIT_KEY_1 ) {    // If KEY_1 is pressed
            while(1) {  // Enter to UART loopback mode.
                uint8_t data = uart_rx();
                if( data == '!' ) break;
                uart_tx(data);
            }
        }
    }
}