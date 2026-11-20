`timescale 1ns / 1ps
module master_subsystem (
    input  wire        clk,
    input  wire        resetn,
    output wire        trap,

    // IRQ từ irq_controller
    input  wire [31:0] irq,

    // AXI4-Lite — APB Bridge port
    output wire [31:0] apb_axi_awaddr,
    output wire        apb_axi_awvalid,
    input  wire        apb_axi_awready,
    output wire [31:0] apb_axi_wdata,
    output wire [ 3:0] apb_axi_wstrb,
    output wire        apb_axi_wvalid,
    input  wire        apb_axi_wready,
    input  wire [ 1:0] apb_axi_bresp,
    input  wire        apb_axi_bvalid,
    output wire        apb_axi_bready,
    output wire [31:0] apb_axi_araddr,
    output wire        apb_axi_arvalid,
    input  wire        apb_axi_arready,
    input  wire [31:0] apb_axi_rdata,
    input  wire [ 1:0] apb_axi_rresp,
    input  wire        apb_axi_rvalid,
    output wire        apb_axi_rready,

    // APB slave — DMA control registers (CPU điều khiển DMA qua APB)
    input  wire [31:0] ext_paddr,        // shared APB bus từ apb_subsystem
    input  wire        ext_penable,
    input  wire        ext_pwrite,
    input  wire [31:0] ext_pwdata,
    input  wire        ext_dma_psel,
    output wire [31:0] ext_dma_prdata,
    output wire        ext_dma_pready,
    output wire        ext_dma_pslverr,

    // APB slave — CRC APB wrapper
    input  wire        ext_crc_psel,
    output wire [31:0] ext_crc_prdata,
    output wire        ext_crc_pready,
    output wire        ext_crc_pslverr,

    // APB slave — AES key config
    input  wire        ext_aes_psel,
    output wire [31:0] ext_aes_prdata,
    output wire        ext_aes_pready,
    output wire        ext_aes_pslverr,

    // DMA IRQ
    output wire        dma_done_irq
);

    // =========================================================================
    // CPU AXI wires
    // =========================================================================
    wire [31:0] cpu_axi_awaddr;
    wire        cpu_axi_awvalid, cpu_axi_awready;
    wire [31:0] cpu_axi_wdata;
    wire [ 3:0] cpu_axi_wstrb;
    wire        cpu_axi_wvalid, cpu_axi_wready;
    wire [ 1:0] cpu_axi_bresp;
    wire        cpu_axi_bvalid, cpu_axi_bready;
    wire [31:0] cpu_axi_araddr;
    wire        cpu_axi_arvalid, cpu_axi_arready;
    wire [31:0] cpu_axi_rdata;
    wire [ 1:0] cpu_axi_rresp;
    wire        cpu_axi_rvalid, cpu_axi_rready;

    // =========================================================================
    // DMA AXI master wires
    // =========================================================================
    wire [31:0] dma_axi_awaddr;
    wire        dma_axi_awvalid, dma_axi_awready;
    wire [31:0] dma_axi_wdata;
    wire [ 3:0] dma_axi_wstrb;
    wire        dma_axi_wvalid, dma_axi_wready;
    wire [ 1:0] dma_axi_bresp;
    wire        dma_axi_bvalid, dma_axi_bready;
    wire [31:0] dma_axi_araddr;
    wire        dma_axi_arvalid, dma_axi_arready;
    wire [31:0] dma_axi_rdata;
    wire [ 1:0] dma_axi_rresp;
    wire        dma_axi_rvalid, dma_axi_rready;

    // =========================================================================
    // ROM / RAM AXI wires
    // =========================================================================
    wire [31:0] rom_axi_araddr;
    wire        rom_axi_arvalid, rom_axi_arready;
    wire [31:0] rom_axi_rdata;
    wire [ 1:0] rom_axi_rresp;
    wire        rom_axi_rvalid, rom_axi_rready;

    wire [31:0] ram_axi_awaddr;
    wire        ram_axi_awvalid, ram_axi_awready;
    wire [31:0] ram_axi_wdata;
    wire [ 3:0] ram_axi_wstrb;
    wire        ram_axi_wvalid, ram_axi_wready;
    wire [ 1:0] ram_axi_bresp;
    wire        ram_axi_bvalid, ram_axi_bready;
    wire [31:0] ram_axi_araddr;
    wire        ram_axi_arvalid, ram_axi_arready;
    wire [31:0] ram_axi_rdata;
    wire [ 1:0] ram_axi_rresp;
    wire        ram_axi_rvalid, ram_axi_rready;

    // =========================================================================
    // CRC internal wires (DMA ↔ crc32_top, nội bộ master_subsystem)
    // =========================================================================
    wire        dma_crc_start, dma_crc_valid, dma_crc_last;
    wire [31:0] dma_crc_data;
    wire        crc_dma_ready;
    wire [31:0] crc_result;
    wire        crc_result_valid;
    wire        crc_result_ack_dma;  // từ DMA
    wire        crc_result_ack_cpu;  // từ crc_apb_wrapper (CPU soft ack)
    wire        crc_result_ack = crc_result_ack_dma | crc_result_ack_cpu;

    // =========================================================================
    // AES internal wires (DMA ↔ aes_top, nội bộ master_subsystem)
    // =========================================================================
    wire        dma_aes_valid_w;
    wire [31:0] dma_aes_data_w;
    wire        aes_dma_ready_w;
    wire        aes_dma_valid_w;
    wire [31:0] aes_dma_data_w;
    wire        dma_aes_ready_w;
    wire [ 3:0] aes_error_code_w;
    wire        aes_error_valid_w;

    // CRC error wires — crc32_top → DMA
    wire [ 3:0] crc_error_code;
    wire        crc_error_valid;

    // =========================================================================
    // CPU (PicoRV32)
    // =========================================================================
    picorv32_axi #(
        .ENABLE_MUL        (0),
        .ENABLE_IRQ        (1),
        .ENABLE_IRQ_QREGS  (1),
        .ENABLE_IRQ_TIMER  (1),
        .ENABLE_DIV        (0),

        .ENABLE_COUNTERS   (0),
        .ENABLE_COUNTERS64 (0),

        .PROGADDR_RESET  (32'h0000_0000),
        .PROGADDR_IRQ    (32'h0000_0010),
        .STACKADDR       (32'h0001_1000)
    ) u_cpu (
        .clk             (clk),
        .resetn          (resetn),
        .trap            (trap),
        .mem_axi_awvalid (cpu_axi_awvalid),
        .mem_axi_awready (cpu_axi_awready),
        .mem_axi_awaddr  (cpu_axi_awaddr),
        .mem_axi_awprot  (),
        .mem_axi_wvalid  (cpu_axi_wvalid),
        .mem_axi_wready  (cpu_axi_wready),
        .mem_axi_wdata   (cpu_axi_wdata),
        .mem_axi_wstrb   (cpu_axi_wstrb),
        .mem_axi_bvalid  (cpu_axi_bvalid),
        .mem_axi_bready  (cpu_axi_bready),
        .mem_axi_arvalid (cpu_axi_arvalid),
        .mem_axi_arready (cpu_axi_arready),
        .mem_axi_araddr  (cpu_axi_araddr),
        .mem_axi_arprot  (),
        .mem_axi_rvalid  (cpu_axi_rvalid),
        .mem_axi_rready  (cpu_axi_rready),
        .mem_axi_rdata   (cpu_axi_rdata),
        .pcpi_valid      (),
        .pcpi_insn       (),
        .pcpi_rs1        (),
        .pcpi_rs2        (),
        .pcpi_wr         (1'b0),
        .pcpi_rd         (32'h0),
        .pcpi_wait       (1'b0),
        .pcpi_ready      (1'b0),
        .irq             (irq),
        .eoi             (),
        .trace_valid     (),
        .trace_data      ()
    );

    // =========================================================================
    // AXI Interconnect (2 masters: CPU + DMA)
    // =========================================================================
    axi_interconnect u_interconnect (
        .clk            (clk),
        .resetn         (resetn),
        // CPU master
        .s_axi_awaddr   (cpu_axi_awaddr),
        .s_axi_awvalid  (cpu_axi_awvalid),
        .s_axi_awready  (cpu_axi_awready),
        .s_axi_wdata    (cpu_axi_wdata),
        .s_axi_wstrb    (cpu_axi_wstrb),
        .s_axi_wvalid   (cpu_axi_wvalid),
        .s_axi_wready   (cpu_axi_wready),
        .s_axi_bresp    (cpu_axi_bresp),
        .s_axi_bvalid   (cpu_axi_bvalid),
        .s_axi_bready   (cpu_axi_bready),
        .s_axi_araddr   (cpu_axi_araddr),
        .s_axi_arvalid  (cpu_axi_arvalid),
        .s_axi_arready  (cpu_axi_arready),
        .s_axi_rdata    (cpu_axi_rdata),
        .s_axi_rresp    (cpu_axi_rresp),
        .s_axi_rvalid   (cpu_axi_rvalid),
        .s_axi_rready   (cpu_axi_rready),
        // DMA master
        .dma_axi_awaddr  (dma_axi_awaddr),
        .dma_axi_awvalid (dma_axi_awvalid),
        .dma_axi_awready (dma_axi_awready),
        .dma_axi_wdata   (dma_axi_wdata),
        .dma_axi_wstrb   (dma_axi_wstrb),
        .dma_axi_wvalid  (dma_axi_wvalid),
        .dma_axi_wready  (dma_axi_wready),
        .dma_axi_bresp   (dma_axi_bresp),
        .dma_axi_bvalid  (dma_axi_bvalid),
        .dma_axi_bready  (dma_axi_bready),
        .dma_axi_araddr  (dma_axi_araddr),
        .dma_axi_arvalid (dma_axi_arvalid),
        .dma_axi_arready (dma_axi_arready),
        .dma_axi_rdata   (dma_axi_rdata),
        .dma_axi_rresp   (dma_axi_rresp),
        .dma_axi_rvalid  (dma_axi_rvalid),
        .dma_axi_rready  (dma_axi_rready),
        // ROM
        .m0_axi_araddr  (rom_axi_araddr),
        .m0_axi_arvalid (rom_axi_arvalid),
        .m0_axi_arready (rom_axi_arready),
        .m0_axi_rdata   (rom_axi_rdata),
        .m0_axi_rresp   (rom_axi_rresp),
        .m0_axi_rvalid  (rom_axi_rvalid),
        .m0_axi_rready  (rom_axi_rready),
        // RAM
        .m1_axi_awaddr  (ram_axi_awaddr),
        .m1_axi_awvalid (ram_axi_awvalid),
        .m1_axi_awready (ram_axi_awready),
        .m1_axi_wdata   (ram_axi_wdata),
        .m1_axi_wstrb   (ram_axi_wstrb),
        .m1_axi_wvalid  (ram_axi_wvalid),
        .m1_axi_wready  (ram_axi_wready),
        .m1_axi_bresp   (ram_axi_bresp),
        .m1_axi_bvalid  (ram_axi_bvalid),
        .m1_axi_bready  (ram_axi_bready),
        .m1_axi_araddr  (ram_axi_araddr),
        .m1_axi_arvalid (ram_axi_arvalid),
        .m1_axi_arready (ram_axi_arready),
        .m1_axi_rdata   (ram_axi_rdata),
        .m1_axi_rresp   (ram_axi_rresp),
        .m1_axi_rvalid  (ram_axi_rvalid),
        .m1_axi_rready  (ram_axi_rready),
        // APB Bridge
        .m2_axi_awaddr  (apb_axi_awaddr),
        .m2_axi_awvalid (apb_axi_awvalid),
        .m2_axi_awready (apb_axi_awready),
        .m2_axi_wdata   (apb_axi_wdata),
        .m2_axi_wstrb   (apb_axi_wstrb),
        .m2_axi_wvalid  (apb_axi_wvalid),
        .m2_axi_wready  (apb_axi_wready),
        .m2_axi_bresp   (apb_axi_bresp),
        .m2_axi_bvalid  (apb_axi_bvalid),
        .m2_axi_bready  (apb_axi_bready),
        .m2_axi_araddr  (apb_axi_araddr),
        .m2_axi_arvalid (apb_axi_arvalid),
        .m2_axi_arready (apb_axi_arready),
        .m2_axi_rdata   (apb_axi_rdata),
        .m2_axi_rresp   (apb_axi_rresp),
        .m2_axi_rvalid  (apb_axi_rvalid),
        .m2_axi_rready  (apb_axi_rready)
    );

    // =========================================================================
    // ROM
    // =========================================================================
    rom u_rom (
        .clk           (clk),
        .resetn        (resetn),
        .s_axi_araddr  (rom_axi_araddr),
        .s_axi_arvalid (rom_axi_arvalid),
        .s_axi_arready (rom_axi_arready),
        .s_axi_rdata   (rom_axi_rdata),
        .s_axi_rresp   (rom_axi_rresp),
        .s_axi_rvalid  (rom_axi_rvalid),
        .s_axi_rready  (rom_axi_rready)
    );

    // =========================================================================
    // RAM
    // =========================================================================
    ram u_ram (
        .clk           (clk),
        .resetn        (resetn),
        .s_axi_awaddr  (ram_axi_awaddr),
        .s_axi_awvalid (ram_axi_awvalid),
        .s_axi_awready (ram_axi_awready),
        .s_axi_wdata   (ram_axi_wdata),
        .s_axi_wstrb   (ram_axi_wstrb),
        .s_axi_wvalid  (ram_axi_wvalid),
        .s_axi_wready  (ram_axi_wready),
        .s_axi_bresp   (ram_axi_bresp),
        .s_axi_bvalid  (ram_axi_bvalid),
        .s_axi_bready  (ram_axi_bready),
        .s_axi_araddr  (ram_axi_araddr),
        .s_axi_arvalid (ram_axi_arvalid),
        .s_axi_arready (ram_axi_arready),
        .s_axi_rdata   (ram_axi_rdata),
        .s_axi_rresp   (ram_axi_rresp),
        .s_axi_rvalid  (ram_axi_rvalid),
        .s_axi_rready  (ram_axi_rready)
    );

    // =========================================================================
    // DMA
    // =========================================================================
    dma u_dma (
        .clk            (clk),
        .rst_n          (resetn),
        // APB slave — nhận từ shared APB bus (ext_*)
        .apb_paddr      (ext_paddr[11:0]),
        .apb_psel       (ext_dma_psel),
        .apb_penable    (ext_penable),
        .apb_pwrite     (ext_pwrite),
        .apb_pwdata     (ext_pwdata),
        .apb_prdata     (ext_dma_prdata),
        .apb_pready     (ext_dma_pready),
        .apb_pslverr    (ext_dma_pslverr),
        // AXI master — đọc/ghi RAM
        .axi_awaddr     (dma_axi_awaddr),
        .axi_awvalid    (dma_axi_awvalid),
        .axi_awready    (dma_axi_awready),
        .axi_wdata      (dma_axi_wdata),
        .axi_wstrb      (dma_axi_wstrb),
        .axi_wvalid     (dma_axi_wvalid),
        .axi_wready     (dma_axi_wready),
        .axi_bresp      (dma_axi_bresp),
        .axi_bvalid     (dma_axi_bvalid),
        .axi_bready     (dma_axi_bready),
        .axi_araddr     (dma_axi_araddr),
        .axi_arvalid    (dma_axi_arvalid),
        .axi_arready    (dma_axi_arready),
        .axi_rdata      (dma_axi_rdata),
        .axi_rresp      (dma_axi_rresp),
        .axi_rvalid     (dma_axi_rvalid),
        .axi_rready     (dma_axi_rready),
        // AES internal stream
        .dma_aes_valid  (dma_aes_valid_w),
        .dma_aes_data   (dma_aes_data_w),
        .aes_dma_ready  (aes_dma_ready_w),
        .aes_dma_valid  (aes_dma_valid_w),
        .aes_dma_data   (aes_dma_data_w),
        .dma_aes_ready  (dma_aes_ready_w),
        .aes_error_code (aes_error_code_w),
        .aes_error_valid(aes_error_valid_w),
        // CRC internal bus
        .dma_crc_start  (dma_crc_start),
        .dma_crc_valid  (dma_crc_valid),
        .dma_crc_data   (dma_crc_data),
        .dma_crc_last   (dma_crc_last),
        .crc_dma_ready  (crc_dma_ready),
        .crc_result     (crc_result),
        .crc_result_valid(crc_result_valid),
        .crc_result_ack (crc_result_ack_dma),
        .crc_error_code (crc_error_code),
        .crc_error_valid(crc_error_valid),
        // IRQ
        .dma_done_irq   (dma_done_irq)
    );

    // =========================================================================
    // CRC32 Top (DMA-facing)
    // =========================================================================
    crc32_top u_crc32 (
        .clk             (clk),
        .rst_n           (resetn),
        .dma_crc_start   (dma_crc_start),
        .dma_crc_valid   (dma_crc_valid),
        .dma_crc_data    (dma_crc_data),
        .dma_crc_last    (dma_crc_last),
        .crc_dma_ready   (crc_dma_ready),
        .crc_result      (crc_result),
        .crc_result_valid(crc_result_valid),
        .crc_result_ack  (crc_result_ack),
        .crc_error_code  (crc_error_code),
        .crc_error_valid (crc_error_valid)
    );

    // =========================================================================
    // CRC APB Wrapper (CPU polling)
    // =========================================================================
    crc_apb_wrapper u_crc_apb (
        .clk             (clk),
        .rst_n           (resetn),
        .apb_paddr       (ext_paddr[11:0]),
        .apb_psel        (ext_crc_psel),
        .apb_penable     (ext_penable),
        .apb_pwrite      (ext_pwrite),
        .apb_pwdata      (ext_pwdata),
        .apb_prdata      (ext_crc_prdata),
        .apb_pready      (ext_crc_pready),
        .apb_pslverr     (ext_crc_pslverr),
        .crc_result      (crc_result),
        .crc_result_valid(crc_result_valid),
        .cpu_crc_ack     (crc_result_ack_cpu)
    );

    // =========================================================================
    // AES top
    // =========================================================================
    aes_top u_aes (
        .clk            (clk),
        .rst_n          (resetn),
        // APB slave — CPU config key
        .psel           (ext_aes_psel),
        .penable        (ext_penable),
        .pwrite         (ext_pwrite),
        .paddr          (ext_paddr[7:0]),
        .pwdata         (ext_pwdata),
        .prdata         (ext_aes_prdata),
        .pready         (ext_aes_pready),
        .pslverr        (ext_aes_pslverr),
        // DMA stream in
        .dma_aes_valid  (dma_aes_valid_w),
        .dma_aes_data   (dma_aes_data_w),
        .aes_dma_ready  (aes_dma_ready_w),
        // DMA stream out
        .aes_dma_valid  (aes_dma_valid_w),
        .aes_dma_data   (aes_dma_data_w),
        .dma_aes_ready  (dma_aes_ready_w),
        // Error → DMA
        .aes_error_code (aes_error_code_w),
        .aes_error_valid(aes_error_valid_w)
    );

endmodule
