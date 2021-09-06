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
static volatile uint32_t* const REG_COUNTER      = (volatile uint32_t*)(0x30000000 + 0x0c*4);
static volatile uint32_t* const REG_CLOCK_HZ     = (volatile uint32_t*)(0x30000000 + 0x0d*4);
static volatile uint32_t* const REG_UART_STATUS  = (volatile uint32_t*)(0x30000000 + 0x0e*4);
static volatile uint32_t* const REG_UART_DATA    = (volatile uint32_t*)(0x30000000 + 0x0f*4);

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
        uint32_t start = *REG_COUNTER;
        while(*REG_COUNTER - start < clock_hz) {
            *REG_COLOR_LED_0 = (*REG_KEY & 0x7);
            *REG_SEG_LED_3 = 0x20 | ((start >> 16) & 0x0f);
            *REG_SEG_LED_2 = 0x20 | ((start >> 20) & 0x0f);
            *REG_SEG_LED_1 = 0x20 | ((start >> 24) & 0x0f);
            *REG_SEG_LED_0 = 0x20 | ((start >> 28) & 0x0f);
        }
        
        if( *REG_KEY & (1u << 6) ) {    // If KEY_6 is pressed
            while(1) {  // Enter to UART loopback mode.
                uint8_t data = uart_rx();
                if( data == '!' ) break;
                uart_tx(data);
            }
        }
    }
}