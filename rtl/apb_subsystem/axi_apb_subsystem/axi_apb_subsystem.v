`timescale 1ns / 1ps
module axi_apb_subsystem #(
    parameter APB_BASE   = 32'h4000_0000,
    parameter UART_BASE  = 32'h4000_0000,
    parameter TIMER_BASE = 32'h4000_1000,
    parameter SPI_BASE   = 32'h4000_2000,
    parameter I2C_BASE   = 32'h4000_3000,
    parameter IRQ_BASE   = 32'h4000_4000,
    parameter DMA_BASE   = 32'h4000_5000,
    parameter CRC_BASE   = 32'h4000_6000,
    parameter AES_BASE   = 32'h4000_7000
)(
    input  wire        clk,
    input  wire        resetn,

    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [ 1:0] s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [ 1:0] s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

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

    // IRQ thẳng lên CPU
    output wire [31:0] irq_out,

    // -------------------------------------------------------------------------
    // DMA APB slave — forward tới master_subsystem
    // -------------------------------------------------------------------------
    output wire [31:0] ext_paddr,
    output wire        ext_penable,
    output wire        ext_pwrite,
    output wire [31:0] ext_pwdata,
    output wire        ext_dma_psel,
    input  wire [31:0] ext_dma_prdata,
    input  wire        ext_dma_pready,
    input  wire        ext_dma_pslverr,

    // -------------------------------------------------------------------------
    // CRC APB wrapper — forward tới master_subsystem
    // -------------------------------------------------------------------------
    output wire        ext_crc_psel,
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

    wire [31:0] apb_paddr,  apb_pwdata, apb_prdata;
    wire        apb_psel,   apb_penable, apb_pwrite;
    wire        apb_pready, apb_pslverr;

    axi_to_apb_bridge #(
        .APB_BASE(APB_BASE)
    ) u_bridge (
        .clk(clk), .resetn(resetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),   .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),   .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),   .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .M_PADDR(apb_paddr), .M_PSEL(apb_psel), .M_PENABLE(apb_penable),
        .M_PWRITE(apb_pwrite), .M_PWDATA(apb_pwdata), .M_PRDATA(apb_prdata),
        .M_PREADY(apb_pready), .M_PSLVERR(apb_pslverr)
    );

    apb_subsystem_top #(
        .UART_BASE (UART_BASE),
        .TIMER_BASE(TIMER_BASE),
        .SPI_BASE  (SPI_BASE),
        .I2C_BASE  (I2C_BASE),
        .IRQ_BASE  (IRQ_BASE),
        .DMA_BASE  (DMA_BASE),
        .CRC_BASE  (CRC_BASE),
        .AES_BASE  (AES_BASE)
    ) u_apb_subsystem (
        .PCLK(clk), .PRESETn(resetn),
        .M_PADDR(apb_paddr), .M_PSEL(apb_psel), .M_PENABLE(apb_penable),
        .M_PWRITE(apb_pwrite), .M_PWDATA(apb_pwdata), .M_PRDATA(apb_prdata),
        .M_PREADY(apb_pready), .M_PSLVERR(apb_pslverr),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .spi_clk(spi_clk), .spi_mosi(spi_mosi), .spi_cs_n(spi_cs_n), .spi_miso(spi_miso),
        .i2c_scl_i(i2c_scl_i), .i2c_scl_o(i2c_scl_o), .i2c_scl_t(i2c_scl_t),
        .i2c_sda_i(i2c_sda_i), .i2c_sda_o(i2c_sda_o), .i2c_sda_t(i2c_sda_t),
        .irq_out(irq_out),
        // DMA/CRC forward
        .ext_paddr(ext_paddr), .ext_penable(ext_penable),
        .ext_pwrite(ext_pwrite), .ext_pwdata(ext_pwdata),
        .ext_dma_psel(ext_dma_psel),
        .ext_dma_prdata(ext_dma_prdata), .ext_dma_pready(ext_dma_pready),
        .ext_dma_pslverr(ext_dma_pslverr),
        .ext_crc_psel(ext_crc_psel),
        .ext_crc_prdata(ext_crc_prdata), .ext_crc_pready(ext_crc_pready),
        .ext_crc_pslverr(ext_crc_pslverr),
        .ext_aes_psel(ext_aes_psel),
        .ext_aes_prdata(ext_aes_prdata), .ext_aes_pready(ext_aes_pready),
        .ext_aes_pslverr(ext_aes_pslverr),
        .dma_done_irq(dma_done_irq)
    );

endmodule
