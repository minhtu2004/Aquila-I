`timescale 1ns / 1ps
module apb_subsystem_top #(
    parameter UART_BASE  = 32'h4000_0000,
    parameter TIMER_BASE = 32'h4000_1000,
    parameter SPI_BASE   = 32'h4000_2000,
    parameter I2C_BASE   = 32'h4000_3000,
    parameter IRQ_BASE   = 32'h4000_4000,
    parameter DMA_BASE   = 32'h4000_5000,
    parameter CRC_BASE   = 32'h4000_6000,
    parameter AES_BASE   = 32'h4000_7000
)(
    input  wire        PCLK,
    input  wire        PRESETn,

    input  wire [31:0] M_PADDR,
    input  wire        M_PSEL,
    input  wire        M_PENABLE,
    input  wire        M_PWRITE,
    input  wire [31:0] M_PWDATA,
    output wire [31:0] M_PRDATA,
    output wire        M_PREADY,
    output wire        M_PSLVERR,

    input  wire        uart_rx,
    output wire        uart_tx,

    output wire        spi_clk,
    output wire        spi_mosi,
    output wire        spi_cs_n,
    input  wire        spi_miso,

    input  wire        i2c_scl_i,
    output wire        i2c_scl_o,
    output wire        i2c_scl_t,
    input  wire        i2c_sda_i,
    output wire        i2c_sda_o,
    output wire        i2c_sda_t,

    // IRQ out thẳng lên CPU
    output wire [31:0] irq_out,

    // -------------------------------------------------------------------------
    // DMA APB slave — forward tới master_subsystem (DMA nằm ở đó)
    // -------------------------------------------------------------------------
    output wire [31:0] ext_paddr,       // shared APB broadcast bus
    output wire        ext_penable,
    output wire        ext_pwrite,
    output wire [31:0] ext_pwdata,
    output wire        ext_dma_psel,    // DMA chip select
    input  wire [31:0] ext_dma_prdata,
    input  wire        ext_dma_pready,
    input  wire        ext_dma_pslverr,

    // -------------------------------------------------------------------------
    // CRC APB wrapper — forward tới master_subsystem (CRC nằm ở đó)
    // -------------------------------------------------------------------------
    output wire        ext_crc_psel,    // CRC chip select
    input  wire [31:0] ext_crc_prdata,
    input  wire        ext_crc_pready,
    input  wire        ext_crc_pslverr,

    // -------------------------------------------------------------------------
    // DMA done IRQ — từ master_subsystem vào irq_controller
    // -------------------------------------------------------------------------
    input  wire        dma_done_irq,

    // -------------------------------------------------------------------------
    // AES APB key config — forward tới master_subsystem
    // -------------------------------------------------------------------------
    output wire        ext_aes_psel,
    input  wire [31:0] ext_aes_prdata,
    input  wire        ext_aes_pready,
    input  wire        ext_aes_pslverr
);

    // Internal bus
    wire [31:0] s_paddr, s_pwdata;
    wire        s_penable, s_pwrite;

    wire uart_psel,  timer_psel,  spi_psel,  i2c_psel,  irq_psel;
    wire dma_psel,   crc_psel,    aes_psel;
    wire [31:0] uart_prdata, timer_prdata, spi_prdata, i2c_prdata, irq_prdata;
    wire        uart_pready, timer_pready, spi_pready, i2c_pready, irq_pready;
    wire        uart_pslverr, timer_pslverr, spi_pslverr, i2c_pslverr, irq_pslverr;

    // Raw IRQ từ peripheral — bit[4] = dma_done_irq
    wire        uart_irq_raw, timer_irq_raw, spi_irq_raw, i2c_irq_raw;
    wire [31:0] raw_irq = {27'b0, dma_done_irq,
                           i2c_irq_raw, spi_irq_raw, timer_irq_raw, uart_irq_raw};

    // 1. APB Interconnect
    apb_interconnect #(
        .UART_BASE (UART_BASE),
        .TIMER_BASE(TIMER_BASE),
        .SPI_BASE  (SPI_BASE),
        .I2C_BASE  (I2C_BASE),
        .IRQ_BASE  (IRQ_BASE),
        .DMA_BASE  (DMA_BASE),
        .CRC_BASE  (CRC_BASE),
        .AES_BASE  (AES_BASE)
    ) u_interconnect (
        .M_PADDR(M_PADDR), .M_PSEL(M_PSEL), .M_PENABLE(M_PENABLE),
        .M_PWRITE(M_PWRITE), .M_PWDATA(M_PWDATA), .M_PRDATA(M_PRDATA),
        .M_PREADY(M_PREADY), .M_PSLVERR(M_PSLVERR),
        .S_PADDR(s_paddr), .S_PENABLE(s_penable),
        .S_PWRITE(s_pwrite), .S_PWDATA(s_pwdata),
        .UART_PSEL(uart_psel),   .UART_PRDATA(uart_prdata),
        .UART_PREADY(uart_pready), .UART_PSLVERR(uart_pslverr),
        .TIMER_PSEL(timer_psel), .TIMER_PRDATA(timer_prdata),
        .TIMER_PREADY(timer_pready), .TIMER_PSLVERR(timer_pslverr),
        .SPI_PSEL(spi_psel),     .SPI_PRDATA(spi_prdata),
        .SPI_PREADY(spi_pready), .SPI_PSLVERR(spi_pslverr),
        .I2C_PSEL(i2c_psel),     .I2C_PRDATA(i2c_prdata),
        .I2C_PREADY(i2c_pready), .I2C_PSLVERR(i2c_pslverr),
        .IRQ_PSEL(irq_psel),     .IRQ_PRDATA(irq_prdata),
        .IRQ_PREADY(irq_pready), .IRQ_PSLVERR(irq_pslverr),
        // DMA/CRC/AES — slave nằm ở master_subsystem, chỉ pass tín hiệu
        .DMA_PSEL(dma_psel),     .DMA_PRDATA(ext_dma_prdata),
        .DMA_PREADY(ext_dma_pready), .DMA_PSLVERR(ext_dma_pslverr),
        .CRC_PSEL(crc_psel),     .CRC_PRDATA(ext_crc_prdata),
        .CRC_PREADY(ext_crc_pready), .CRC_PSLVERR(ext_crc_pslverr),
        .AES_PSEL(aes_psel),     .AES_PRDATA(ext_aes_prdata),
        .AES_PREADY(ext_aes_pready), .AES_PSLVERR(ext_aes_pslverr)
    );

    // Forward shared bus + psel ra ngoài cho master_subsystem
    assign ext_paddr    = s_paddr;
    assign ext_penable  = s_penable;
    assign ext_pwrite   = s_pwrite;
    assign ext_pwdata   = s_pwdata;
    assign ext_dma_psel = dma_psel;
    assign ext_crc_psel = crc_psel;
    assign ext_aes_psel = aes_psel;

    // 2. UART
    uart_apb_wrapper u_uart (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PSEL(uart_psel), .PENABLE(s_penable), .PWRITE(s_pwrite),
        .PADDR(s_paddr), .PWDATA(s_pwdata), .PRDATA(uart_prdata),
        .PREADY(uart_pready), .PSLVERR(uart_pslverr),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_irq(uart_irq_raw)
    );

    // 3. TIMER
    timer_apb_wrapper u_timer (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PSEL(timer_psel), .PENABLE(s_penable), .PWRITE(s_pwrite),
        .PADDR(s_paddr), .PWDATA(s_pwdata), .PRDATA(timer_prdata),
        .PREADY(timer_pready), .PSLVERR(timer_pslverr),
        .timer_irq(timer_irq_raw)
    );

    // 4. SPI
    spi_apb_wrapper u_spi (
        .pclk(PCLK), .presetn(PRESETn),
        .psel(spi_psel), .penable(s_penable), .pwrite(s_pwrite),
        .paddr(s_paddr[7:0]), .pwdata(s_pwdata), .prdata(spi_prdata),
        .pready(spi_pready), .pslverr(spi_pslverr),
        .o_spi_irq(spi_irq_raw), .o_SPI_Clk(spi_clk), .o_SPI_MOSI(spi_mosi),
        .o_SPI_CS_n(spi_cs_n), .i_SPI_MISO(spi_miso)
    );

    // 5. I2C
    i2c_apb_wrapper u_i2c (
        .pclk(PCLK), .presetn(PRESETn),
        .psel(i2c_psel), .penable(s_penable), .pwrite(s_pwrite),
        .paddr(s_paddr[7:0]), .pwdata(s_pwdata), .prdata(i2c_prdata),
        .pready(i2c_pready), .pslverr(i2c_pslverr),
        .o_i2c_irq(i2c_irq_raw), .scl_i(i2c_scl_i), .scl_o(i2c_scl_o),
        .scl_t(i2c_scl_t), .sda_i(i2c_sda_i), .sda_o(i2c_sda_o), .sda_t(i2c_sda_t)
    );

    // 6. IRQ Controller
    irq_controller #(
        .N_IRQ(32)
    ) u_irq_ctrl (
        .pclk(PCLK), .presetn(PRESETn),
        .paddr(s_paddr[7:0]), .psel(irq_psel),
        .penable(s_penable), .pwrite(s_pwrite),
        .pwdata(s_pwdata), .prdata(irq_prdata),
        .pready(irq_pready), .pslverr(irq_pslverr),
        .raw_irq(raw_irq),
        .irq_out(irq_out)
    );

    // synthesis translate_off
    initial begin
        if (UART_BASE[11:0]  != 12'h000) begin $error("UART_BASE not 4KB aligned");  $finish; end
        if (TIMER_BASE[11:0] != 12'h000) begin $error("TIMER_BASE not 4KB aligned"); $finish; end
        if (SPI_BASE[11:0]   != 12'h000) begin $error("SPI_BASE not 4KB aligned");   $finish; end
        if (I2C_BASE[11:0]   != 12'h000) begin $error("I2C_BASE not 4KB aligned");   $finish; end
        if (IRQ_BASE[11:0]   != 12'h000) begin $error("IRQ_BASE not 4KB aligned");   $finish; end
        if (DMA_BASE[11:0]   != 12'h000) begin $error("DMA_BASE not 4KB aligned");   $finish; end
        if (CRC_BASE[11:0]   != 12'h000) begin $error("CRC_BASE not 4KB aligned");   $finish; end
        if (AES_BASE[11:0]   != 12'h000) begin $error("AES_BASE not 4KB aligned");   $finish; end
    end
    // synthesis translate_on

endmodule
