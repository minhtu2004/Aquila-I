`timescale 1ns / 1ps
module soc_top (
    input  wire        clk,
    input  wire        resetn,
    output wire        trap,

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
    output wire        i2c_sda_t
);

    // =========================================================================
    // AXI wires: master_subsystem ↔ axi_apb_subsystem
    // =========================================================================
    wire [31:0] apb_axi_awaddr;
    wire        apb_axi_awvalid, apb_axi_awready;
    wire [31:0] apb_axi_wdata;
    wire [ 3:0] apb_axi_wstrb;
    wire        apb_axi_wvalid, apb_axi_wready;
    wire [ 1:0] apb_axi_bresp;
    wire        apb_axi_bvalid, apb_axi_bready;
    wire [31:0] apb_axi_araddr;
    wire        apb_axi_arvalid, apb_axi_arready;
    wire [31:0] apb_axi_rdata;
    wire [ 1:0] apb_axi_rresp;
    wire        apb_axi_rvalid, apb_axi_rready;

    wire [31:0] irq_out;

    // =========================================================================
    // APB cross-subsystem wires: DMA/CRC APB + dma_done_irq
    // =========================================================================
    wire [31:0] ext_paddr;
    wire        ext_penable, ext_pwrite;
    wire [31:0] ext_pwdata;

    wire        ext_dma_psel;
    wire [31:0] ext_dma_prdata;
    wire        ext_dma_pready, ext_dma_pslverr;

    wire        ext_crc_psel;
    wire [31:0] ext_crc_prdata;
    wire        ext_crc_pready, ext_crc_pslverr;

    wire        ext_aes_psel;
    wire [31:0] ext_aes_prdata;
    wire        ext_aes_pready, ext_aes_pslverr;

    wire        dma_done_irq;

    // =========================================================================
    // Master Subsystem (CPU + DMA + CRC logic)
    // =========================================================================
    master_subsystem u_master (
        .clk             (clk),
        .resetn          (resetn),
        .trap            (trap),
        .irq             (irq_out),
        // AXI → APB Bridge
        .apb_axi_awaddr  (apb_axi_awaddr),
        .apb_axi_awvalid (apb_axi_awvalid),
        .apb_axi_awready (apb_axi_awready),
        .apb_axi_wdata   (apb_axi_wdata),
        .apb_axi_wstrb   (apb_axi_wstrb),
        .apb_axi_wvalid  (apb_axi_wvalid),
        .apb_axi_wready  (apb_axi_wready),
        .apb_axi_bresp   (apb_axi_bresp),
        .apb_axi_bvalid  (apb_axi_bvalid),
        .apb_axi_bready  (apb_axi_bready),
        .apb_axi_araddr  (apb_axi_araddr),
        .apb_axi_arvalid (apb_axi_arvalid),
        .apb_axi_arready (apb_axi_arready),
        .apb_axi_rdata   (apb_axi_rdata),
        .apb_axi_rresp   (apb_axi_rresp),
        .apb_axi_rvalid  (apb_axi_rvalid),
        .apb_axi_rready  (apb_axi_rready),
        // DMA APB slave (shared bus từ apb_subsystem)
        .ext_paddr       (ext_paddr),
        .ext_penable     (ext_penable),
        .ext_pwrite      (ext_pwrite),
        .ext_pwdata      (ext_pwdata),
        .ext_dma_psel    (ext_dma_psel),
        .ext_dma_prdata  (ext_dma_prdata),
        .ext_dma_pready  (ext_dma_pready),
        .ext_dma_pslverr (ext_dma_pslverr),
        // CRC APB wrapper
        .ext_crc_psel    (ext_crc_psel),
        .ext_crc_prdata  (ext_crc_prdata),
        .ext_crc_pready  (ext_crc_pready),
        .ext_crc_pslverr (ext_crc_pslverr),
        // AES APB key config
        .ext_aes_psel    (ext_aes_psel),
        .ext_aes_prdata  (ext_aes_prdata),
        .ext_aes_pready  (ext_aes_pready),
        .ext_aes_pslverr (ext_aes_pslverr),
        // DMA IRQ
        .dma_done_irq    (dma_done_irq)
    );

    // =========================================================================
    // APB Subsystem (APB decode + UART/Timer/SPI/I2C/IRQ)
    // =========================================================================
    axi_apb_subsystem u_apb (
        .clk          (clk),
        .resetn       (resetn),
        .s_axi_awaddr (apb_axi_awaddr),
        .s_axi_awvalid(apb_axi_awvalid),
        .s_axi_awready(apb_axi_awready),
        .s_axi_wdata  (apb_axi_wdata),
        .s_axi_wstrb  (apb_axi_wstrb),
        .s_axi_wvalid (apb_axi_wvalid),
        .s_axi_wready (apb_axi_wready),
        .s_axi_bresp  (apb_axi_bresp),
        .s_axi_bvalid (apb_axi_bvalid),
        .s_axi_bready (apb_axi_bready),
        .s_axi_araddr (apb_axi_araddr),
        .s_axi_arvalid(apb_axi_arvalid),
        .s_axi_arready(apb_axi_arready),
        .s_axi_rdata  (apb_axi_rdata),
        .s_axi_rresp  (apb_axi_rresp),
        .s_axi_rvalid (apb_axi_rvalid),
        .s_axi_rready (apb_axi_rready),
        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .spi_clk      (spi_clk),
        .spi_mosi     (spi_mosi),
        .spi_cs_n     (spi_cs_n),
        .spi_miso     (spi_miso),
        .i2c_scl_i    (i2c_scl_i),
        .i2c_scl_o    (i2c_scl_o),
        .i2c_scl_t    (i2c_scl_t),
        .i2c_sda_i    (i2c_sda_i),
        .i2c_sda_o    (i2c_sda_o),
        .i2c_sda_t    (i2c_sda_t),
        .irq_out      (irq_out),
        // DMA/CRC APB forward
        .ext_paddr       (ext_paddr),
        .ext_penable     (ext_penable),
        .ext_pwrite      (ext_pwrite),
        .ext_pwdata      (ext_pwdata),
        .ext_dma_psel    (ext_dma_psel),
        .ext_dma_prdata  (ext_dma_prdata),
        .ext_dma_pready  (ext_dma_pready),
        .ext_dma_pslverr (ext_dma_pslverr),
        .ext_crc_psel    (ext_crc_psel),
        .ext_crc_prdata  (ext_crc_prdata),
        .ext_crc_pready  (ext_crc_pready),
        .ext_crc_pslverr (ext_crc_pslverr),
        .ext_aes_psel    (ext_aes_psel),
        .ext_aes_prdata  (ext_aes_prdata),
        .ext_aes_pready  (ext_aes_pready),
        .ext_aes_pslverr (ext_aes_pslverr),
        .dma_done_irq    (dma_done_irq)
    );

endmodule
