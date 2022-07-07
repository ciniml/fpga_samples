#include <stdint.h>
#include <stdbool.h>

extern void __attribute__((naked)) __attribute__((section(".isr_vector"))) isr_vector(void)
{
    asm volatile ("j _start");
    asm volatile ("j _start");
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

extern void __attribute__((naked)) _start(void)
{
    asm volatile ("la sp, ramend");
    asm volatile ("addi sp, sp, -4");
    init();
    main();
}

typedef struct {
    uint32_t output;
    uint32_t input;
    uint32_t output_enable;
} gpio_regs;

static volatile gpio_regs* const REG_GPIO = (volatile gpio_regs*)0x30000000;
static volatile uint32_t* const REG_UART_DATA = (volatile uint32_t*)0x30001000;
static volatile uint32_t* const REG_UART_STATUS = (volatile uint32_t*)0x30001004;
static volatile uint32_t* const REG_CONFIG_ID = (volatile uint32_t*)0x40000000;
static volatile uint32_t* const REG_CONFIG_CLOCK_HZ = (volatile uint32_t*)0x40000004;
static volatile uint32_t* const REG_MATRIX_BASE = (volatile uint32_t*)0x50000000;

#define GPIO_LED_MASK (0b00011111)
#define GPIO_DEBUG_BIT (12)
#define GPIO_LCD_BIT (8)
#define GPIO_LCD_DB_MASK (0b00001111 << GPIO_LCD_BIT)
#define GPIO_LCD_RS_MASK (0b00010000 << GPIO_LCD_BIT)
#define GPIO_LCD_RW_MASK (0b00100000 << GPIO_LCD_BIT)
#define GPIO_LCD_E_MASK (0b01000000 << GPIO_LCD_BIT)

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
    while((*REG_UART_STATUS & 0b01) != 0);
    *REG_UART_DATA = value;
}
static bool uart_rx_ready(void) {
    return (*REG_UART_STATUS & 0b10) != 0;
}
static uint8_t uart_rx() 
{
    while(!uart_rx_ready());
    return *REG_UART_DATA;
}

static void uart_puts(const char* s)
{
    while(*s) {
        uart_tx((uint8_t)*(s++));
    }
}

static const uint64_t DURATION_US_FACTOR = ((uint64_t)1 << 32) / 1000000u;

static void wait_cycles(uint64_t cycles)
{
    uint64_t start = read_cycle();
    while(read_cycle() - start < cycles);
}
static void delay_us(uint32_t duration_us)
{
    wait_cycles(duration_us * 27);
}

static void led_set_out(uint32_t led) {
    REG_GPIO->output = (REG_GPIO->output & ~GPIO_LED_MASK) | led;
}

static inline void debug_out(uint32_t debug) {
    REG_GPIO->output = (REG_GPIO->output & ~(0b1111 << GPIO_DEBUG_BIT)) | ((debug & 0b1111) << GPIO_DEBUG_BIT);
}

static void lcd_set_rs(uint32_t value) {
    REG_GPIO->output = (REG_GPIO->output & ~GPIO_LCD_RS_MASK) | (value ? GPIO_LCD_RS_MASK : 0);
}
static void lcd_set_rw(uint32_t value) {
    REG_GPIO->output_enable = (REG_GPIO->output_enable & ~GPIO_LCD_DB_MASK) | (value ? 0 : GPIO_LCD_DB_MASK);
    REG_GPIO->output = (REG_GPIO->output & ~GPIO_LCD_RW_MASK) | (value ? GPIO_LCD_RW_MASK : 0);
}
static void lcd_set_e(uint32_t value) {
    REG_GPIO->output = (REG_GPIO->output & ~GPIO_LCD_E_MASK) | (value ? GPIO_LCD_E_MASK : 0);
}
static void lcd_db_out(uint32_t value) {
    REG_GPIO->output = (REG_GPIO->output & ~GPIO_LCD_DB_MASK) | (value << GPIO_LCD_BIT);
}
static uint32_t lcd_db_in() {
    return (REG_GPIO->input >> GPIO_LCD_BIT) & 0x0f;
}
static uint32_t lcd_write_half(uint8_t command_half) {
    lcd_set_e(0);
    lcd_db_out(command_half);
    lcd_set_rw(0);
    delay_us(25);
    lcd_set_e(1);
    delay_us(3);
    lcd_set_e(0);
    delay_us(2);
}

static uint32_t lcd_write_command(uint8_t command) {
    lcd_set_rs(0);
    lcd_write_half(command >> 4);
    lcd_write_half(command & 0xf);
}

static uint32_t lcd_write_data(uint8_t data) {
    lcd_set_rs(1);
    lcd_write_half(data >> 4);
    lcd_write_half(data & 0xf);
}

static uint32_t lcd_set_ddram_address(uint8_t address) {
    lcd_write_command(0b10000000 | (address & 0b01111111));
    delay_us(37);
}

static void lcd_clear(void) {
    lcd_write_command(0b00000001);
    delay_us(20000);
}

static uint32_t lcd_counter = 0;
static void lcd_put_char(uint8_t c) {
    if( lcd_counter == 16 ) {
        lcd_set_ddram_address(0x40);
    } 
    else if( lcd_counter == 32 ) {
        lcd_clear();
        lcd_counter = 0;
    }
    lcd_write_data(c);
    delay_us(37);
    lcd_counter++;
}

static void lcd_init(void) {
    // Force entering to 4bit bus mode.
    lcd_set_rs(0);
    delay_us(500000);
    lcd_write_half(0b0011);
    delay_us(41000);
    lcd_write_half(0b0011);
    delay_us(100);
    lcd_write_half(0b0011);
    lcd_write_half(0b0010);

    // Function set
    lcd_write_command(0b00101000);  // 2 rows,8 lines
    delay_us(37);
    // Clear
    lcd_clear();
    // Entry mode set
    lcd_write_command(0b00000110);
    delay_us(37);
    // Show
    lcd_write_command(0b00001111);  // Show characters, under line cursor, block cursor.
    delay_us(37);
}

void __attribute__((noreturn)) main(void)
{
    uint32_t led_out = 1;
    uint32_t clock_hz = *REG_CONFIG_CLOCK_HZ;
    uint32_t matrix_up = 1;
    static volatile uint32_t matrix[2] = {0, 0};
    static volatile uint32_t seven_seg = 1;

    // Initialize character LCD and put A-Z characters
    lcd_init();
    for(uint8_t c = 'A'; c <= 'Z'; c++) {
       lcd_put_char(c);
    }
    uart_puts("Hello, RISC-V\r\n");
    
    uint64_t last_processed = read_cycle();

    while(1) {
        uint64_t now = read_cycle();
        if(now - last_processed > (clock_hz >> 1)) {
            last_processed = now;
            led_set_out(led_out);
            led_out = (led_out << 1) | ((led_out >> 7) & 1);
            if( matrix_up ) {
                matrix[1] = (matrix[1] << 1) | (matrix[0] == 0xffffffff ? 1 : 0);
                matrix[0] = (matrix[0] << 1) | 1;
                matrix_up = matrix[0] == 0xffffffff && matrix[1] == 0xffffffff ? 0 : 1;
            }
            else {
                matrix[1] = (matrix[1] << 1) | (matrix[0] != 0 ? 1 : 0);
                matrix[0] = (matrix[0] << 1);
                matrix_up = matrix[0] == 0 && matrix[1] == 0 ? 1 : 0;
            }
            *(REG_MATRIX_BASE + 0) = matrix[0];
            *(REG_MATRIX_BASE + 1) = matrix[1];

            *(REG_MATRIX_BASE + 2) = seven_seg;
            seven_seg = seven_seg == 0b10000000 ? 1 : seven_seg << 1;
        }
        if( uart_rx_ready() ) { // Receive a character from UART and put it to the LCD.
            uint8_t c = uart_rx();
            lcd_put_char(c);
            uart_tx(c);
        }
    }
}