/**
 * Copyright (c) 2025 Kenta Ida
 *
 * SPDX-License-Identifier: BSL-1.0
 */

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>

#include "pico/stdlib.h"
#include "pico/binary_info.h"
#include "hardware/spi.h"
#include "hardware/dma.h"

#include "image.h"

static constexpr std::size_t BUFFER_SIZE = 16384;

static void transfer_spi_with_dma(const void* txbuf, void* rxbuf, std::size_t transfer_length) {
    
    // Grab some unused dma channels
    const uint dma_tx = dma_claim_unused_channel(true);
    const uint dma_rx = dma_claim_unused_channel(true);

    gpio_put(PICO_DEFAULT_SPI_CSN_PIN, 0);

    // We set the outbound DMA to transfer from a memory buffer to the SPI transmit FIFO paced by the SPI TX FIFO DREQ
    // The default is for the read address to increment every element (in this case 1 byte = DMA_SIZE_8)
    // and for the write address to remain unchanged.

    dma_channel_config c = dma_channel_get_default_config(dma_tx);
    channel_config_set_transfer_data_size(&c, DMA_SIZE_8);
    channel_config_set_dreq(&c, spi_get_dreq(spi_default, true));
    dma_channel_configure(dma_tx, &c,
                        &spi_get_hw(spi_default)->dr, // write address
                        txbuf, // read address
                        transfer_length, // element count (each element is of size transfer_data_size)
                        false); // don't start yet

    // We set the inbound DMA to transfer from the SPI receive FIFO to a memory buffer paced by the SPI RX FIFO DREQ
    // We configure the read address to remain unchanged for each element, but the write
    // address to increment (so data is written throughout the buffer)
    c = dma_channel_get_default_config(dma_rx);
    channel_config_set_transfer_data_size(&c, DMA_SIZE_8);
    channel_config_set_dreq(&c, spi_get_dreq(spi_default, false));
    channel_config_set_read_increment(&c, false);
    channel_config_set_write_increment(&c, true);
    dma_channel_configure(dma_rx, &c,
                        rxbuf, // write address
                        &spi_get_hw(spi_default)->dr, // read address
                        transfer_length, // element count (each element is of size transfer_data_size)
                        false); // don't start yet


    // start them exactly simultaneously to avoid races (in extreme cases the FIFO could overflow)
    dma_start_channel_mask((1u << dma_tx) | (1u << dma_rx));
    dma_channel_wait_for_finish_blocking(dma_rx);
    if (dma_channel_is_busy(dma_tx)) {
        panic("RX completed before TX");
    }

    gpio_put(PICO_DEFAULT_SPI_CSN_PIN, 1);

    dma_channel_unclaim(dma_tx);
    dma_channel_unclaim(dma_rx);
}

int main() {
    // Enable UART so we can print status output
    stdio_init_all();

    // Enable SPI at 80 MHz and connect to GPIOs
    spi_init(spi_default, 1000 * 1000 * 60);
    gpio_set_function(PICO_DEFAULT_SPI_RX_PIN, GPIO_FUNC_SPI);
    gpio_init(PICO_DEFAULT_SPI_CSN_PIN);
    gpio_set_dir(PICO_DEFAULT_SPI_CSN_PIN, GPIO_OUT);
    gpio_put(PICO_DEFAULT_SPI_CSN_PIN, 1);


    gpio_set_function(PICO_DEFAULT_SPI_SCK_PIN, GPIO_FUNC_SPI);
    gpio_set_function(PICO_DEFAULT_SPI_TX_PIN, GPIO_FUNC_SPI);
    // Make the SPI pins available to picotool
    bi_decl(bi_3pins_with_func(PICO_DEFAULT_SPI_RX_PIN, PICO_DEFAULT_SPI_TX_PIN, PICO_DEFAULT_SPI_SCK_PIN, GPIO_FUNC_SPI));
    // Make the CS pin available to picotool
    bi_decl(bi_1pin_with_name(PICO_DEFAULT_SPI_CSN_PIN, "SPI CS"));

    static uint8_t txbuf[BUFFER_SIZE];
    static uint8_t rxbuf[BUFFER_SIZE];

    while(true) {
        std::size_t command_length = 0;
        constexpr std::size_t SCREEN_WIDTH = 70;
        constexpr std::size_t SCREEN_HEIGHT = 90;
        std::size_t x = rand() % SCREEN_WIDTH;
        std::size_t y = rand() % SCREEN_HEIGHT;
        std::size_t w = rand() % SCREEN_WIDTH;
        std::size_t h = rand() % SCREEN_HEIGHT;
        std::uint8_t color = rand() & 0xff;
        w = x + w >= SCREEN_WIDTH ? SCREEN_WIDTH - x - 1 : w;
        h = y + h >= SCREEN_HEIGHT ? SCREEN_HEIGHT - y - 1 : h;
        txbuf[command_length++] = 0x20;
        txbuf[command_length++] = ((x + 90) >> 8);
        txbuf[command_length++] = ((x + 90) & 0xff);
        txbuf[command_length++] = (y >> 8);
        txbuf[command_length++] = (y & 0xff);
        txbuf[command_length++] = (w >> 8);
        txbuf[command_length++] = (w & 0xff);
        txbuf[command_length++] = (h >> 8);
        txbuf[command_length++] = (h & 0xff);
        txbuf[command_length++] = color;

        transfer_spi_with_dma(txbuf, rxbuf, command_length);
        sleep_ms(1);

        command_length = 0;
        x = 0;
        y = 0;
        w = 90 - 1;
        h = 90 - 1;
        txbuf[command_length++] = 0x30;
        txbuf[command_length++] = (x >> 8);
        txbuf[command_length++] = (x & 0xff);
        txbuf[command_length++] = (y >> 8);
        txbuf[command_length++] = (y & 0xff);
        txbuf[command_length++] = (w >> 8);
        txbuf[command_length++] = (w & 0xff);
        txbuf[command_length++] = (h >> 8);
        txbuf[command_length++] = (h & 0xff);
        std::memcpy(&txbuf[command_length], ___fuga_300px_90h_rgb332_bin, sizeof(___fuga_300px_90h_rgb332_bin));
        command_length += sizeof(___fuga_300px_90h_rgb332_bin);

        transfer_spi_with_dma(txbuf, rxbuf, command_length);
        sleep_ms(1);
        
        // WRITE_PIXEL
        x = rand() % SCREEN_WIDTH;
        y = rand() % SCREEN_HEIGHT;
        color = rand() & 0xff;
        txbuf[command_length++] = 0x40;
        txbuf[command_length++] = ((x + 90) >> 8);
        txbuf[command_length++] = ((x + 90) & 0xff);
        txbuf[command_length++] = (y >> 8);
        txbuf[command_length++] = (y & 0xff);
        txbuf[command_length++] = color;

        transfer_spi_with_dma(txbuf, rxbuf, command_length);
        sleep_us(10);
    }
    
    return 0;
}
