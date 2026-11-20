`timescale 1ns / 1ps
module apb_interconnect #(
    parameter UART_BASE  = 32'h4000_0000,
    parameter TIMER_BASE = 32'h4000_1000,
    parameter SPI_BASE   = 32'h4000_2000,
    parameter I2C_BASE   = 32'h4000_3000,
    parameter IRQ_BASE   = 32'h4000_4000,
    parameter DMA_BASE   = 32'h4000_5000,
    parameter CRC_BASE   = 32'h4000_6000,
    parameter AES_BASE   = 32'h4000_7000
)(
    // --- Master Interface ---
    input  wire [31:0] M_PADDR,
    input  wire        M_PSEL,
    input  wire        M_PENABLE,
    input  wire        M_PWRITE,
    input  wire [31:0] M_PWDATA,
    output wire [31:0] M_PRDATA,
    output wire        M_PREADY,
    output wire        M_PSLVERR,
    // --- Broadcast (shared bus đến tất cả slave) ---
    output wire [31:0] S_PADDR,
    output wire        S_PENABLE,
    output wire        S_PWRITE,
    output wire [31:0] S_PWDATA,
    // --- UART ---
    output wire        UART_PSEL,
    input  wire [31:0] UART_PRDATA,
    input  wire        UART_PREADY,
    input  wire        UART_PSLVERR,
    // --- TIMER ---
    output wire        TIMER_PSEL,
    input  wire [31:0] TIMER_PRDATA,
    input  wire        TIMER_PREADY,
    input  wire        TIMER_PSLVERR,
    // --- SPI ---
    output wire        SPI_PSEL,
    input  wire [31:0] SPI_PRDATA,
    input  wire        SPI_PREADY,
    input  wire        SPI_PSLVERR,
    // --- I2C ---
    output wire        I2C_PSEL,
    input  wire [31:0] I2C_PRDATA,
    input  wire        I2C_PREADY,
    input  wire        I2C_PSLVERR,
    // --- IRQ CTRL ---
    output wire        IRQ_PSEL,
    input  wire [31:0] IRQ_PRDATA,
    input  wire        IRQ_PREADY,
    input  wire        IRQ_PSLVERR,
    // --- DMA config (slave nằm trong master_subsystem) ---
    output wire        DMA_PSEL,
    input  wire [31:0] DMA_PRDATA,
    input  wire        DMA_PREADY,
    input  wire        DMA_PSLVERR,
    // --- CRC APB wrapper (slave nằm trong master_subsystem) ---
    output wire        CRC_PSEL,
    input  wire [31:0] CRC_PRDATA,
    input  wire        CRC_PREADY,
    input  wire        CRC_PSLVERR,
    // --- AES APB key config (slave nằm trong master_subsystem) ---
    output wire        AES_PSEL,
    input  wire [31:0] AES_PRDATA,
    input  wire        AES_PREADY,
    input  wire        AES_PSLVERR
);
    wire sel_uart  = M_PSEL && (M_PADDR[31:12] == UART_BASE[31:12]);
    wire sel_timer = M_PSEL && (M_PADDR[31:12] == TIMER_BASE[31:12]);
    wire sel_spi   = M_PSEL && (M_PADDR[31:12] == SPI_BASE[31:12]);
    wire sel_i2c   = M_PSEL && (M_PADDR[31:12] == I2C_BASE[31:12]);
    wire sel_irq   = M_PSEL && (M_PADDR[31:12] == IRQ_BASE[31:12]);
    wire sel_dma   = M_PSEL && (M_PADDR[31:12] == DMA_BASE[31:12]);
    wire sel_crc   = M_PSEL && (M_PADDR[31:12] == CRC_BASE[31:12]);
    wire sel_aes   = M_PSEL && (M_PADDR[31:12] == AES_BASE[31:12]);
    wire sel_none  = M_PSEL && !(sel_uart || sel_timer || sel_spi || sel_i2c ||
                                  sel_irq  || sel_dma   || sel_crc || sel_aes);

    assign S_PADDR   = M_PADDR;
    assign S_PENABLE = M_PENABLE;
    assign S_PWRITE  = M_PWRITE;
    assign S_PWDATA  = M_PWDATA;

    assign UART_PSEL  = sel_uart;
    assign TIMER_PSEL = sel_timer;
    assign SPI_PSEL   = sel_spi;
    assign I2C_PSEL   = sel_i2c;
    assign IRQ_PSEL   = sel_irq;
    assign DMA_PSEL   = sel_dma;
    assign CRC_PSEL   = sel_crc;
    assign AES_PSEL   = sel_aes;

    assign M_PRDATA  = ({32{sel_uart}}  & UART_PRDATA)  |
                       ({32{sel_timer}} & TIMER_PRDATA) |
                       ({32{sel_spi}}   & SPI_PRDATA)   |
                       ({32{sel_i2c}}   & I2C_PRDATA)   |
                       ({32{sel_irq}}   & IRQ_PRDATA)   |
                       ({32{sel_dma}}   & DMA_PRDATA)   |
                       ({32{sel_crc}}   & CRC_PRDATA)   |
                       ({32{sel_aes}}   & AES_PRDATA);

    assign M_PREADY  = sel_uart  ? UART_PREADY  :
                       sel_timer ? TIMER_PREADY :
                       sel_spi   ? SPI_PREADY   :
                       sel_i2c   ? I2C_PREADY   :
                       sel_irq   ? IRQ_PREADY   :
                       sel_dma   ? DMA_PREADY   :
                       sel_crc   ? CRC_PREADY   :
                       sel_aes   ? AES_PREADY   : 1'b1;

    assign M_PSLVERR = sel_uart  ? UART_PSLVERR  :
                       sel_timer ? TIMER_PSLVERR :
                       sel_spi   ? SPI_PSLVERR   :
                       sel_i2c   ? I2C_PSLVERR   :
                       sel_irq   ? IRQ_PSLVERR   :
                       sel_dma   ? DMA_PSLVERR   :
                       sel_crc   ? CRC_PSLVERR   :
                       sel_aes   ? AES_PSLVERR   :
                       sel_none  ? 1'b1          : 1'b0;
endmodule
