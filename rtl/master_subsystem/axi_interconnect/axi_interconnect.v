`timescale 1ns / 1ps
// =============================================================================
// AXI4-Lite Interconnect
// 2 Masters (CPU, DMA), 3 Slaves (ROM / RAM / APB Bridge)
// -----------------------------------------------------------------------------
// Address Map:
//   ROM  : 0x0000_0000 - 0x0000_1FFF (8KB,  Read-Only)
//   RAM  : 0x0001_0000 - 0x0001_0FFF (4KB)
//   APB  : 0x4000_0000 - 0x4FFF_FFFF
// -----------------------------------------------------------------------------
// Default Slave: địa chỉ không hợp lệ → DECERR (bresp/rresp = 2'b11)
// Arbiter: fixed priority CPU > DMA
//   DMA chỉ được phép truy cập RAM; địa chỉ khác → DECERR
// =============================================================================
module axi_interconnect (
    input  wire clk,
    input  wire resetn,

    // -------------------------------------------------------------------------
    // Master Port 0: CPU
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Master Port 1: DMA — fixed priority below CPU
    // -------------------------------------------------------------------------
    input  wire [31:0] dma_axi_awaddr,
    input  wire        dma_axi_awvalid,
    output wire        dma_axi_awready,
    input  wire [31:0] dma_axi_wdata,
    input  wire [ 3:0] dma_axi_wstrb,
    input  wire        dma_axi_wvalid,
    output wire        dma_axi_wready,
    output wire [ 1:0] dma_axi_bresp,
    output wire        dma_axi_bvalid,
    input  wire        dma_axi_bready,
    input  wire [31:0] dma_axi_araddr,
    input  wire        dma_axi_arvalid,
    output wire        dma_axi_arready,
    output wire [31:0] dma_axi_rdata,
    output wire [ 1:0] dma_axi_rresp,
    output wire        dma_axi_rvalid,
    input  wire        dma_axi_rready,

    // -------------------------------------------------------------------------
    // Slave 0: ROM — Read Only (0x0000_0000)
    // -------------------------------------------------------------------------
    output wire [31:0] m0_axi_araddr,
    output wire        m0_axi_arvalid,
    input  wire        m0_axi_arready,
    input  wire [31:0] m0_axi_rdata,
    input  wire [ 1:0] m0_axi_rresp,
    input  wire        m0_axi_rvalid,
    output wire        m0_axi_rready,

    // -------------------------------------------------------------------------
    // Slave 1: RAM (0x0001_0000)
    // -------------------------------------------------------------------------
    output wire [31:0] m1_axi_awaddr,
    output wire        m1_axi_awvalid,
    input  wire        m1_axi_awready,
    output wire [31:0] m1_axi_wdata,
    output wire [ 3:0] m1_axi_wstrb,
    output wire        m1_axi_wvalid,
    input  wire        m1_axi_wready,
    input  wire [ 1:0] m1_axi_bresp,
    input  wire        m1_axi_bvalid,
    output wire        m1_axi_bready,
    output wire [31:0] m1_axi_araddr,
    output wire        m1_axi_arvalid,
    input  wire        m1_axi_arready,
    input  wire [31:0] m1_axi_rdata,
    input  wire [ 1:0] m1_axi_rresp,
    input  wire        m1_axi_rvalid,
    output wire        m1_axi_rready,

    // -------------------------------------------------------------------------
    // Slave 2: APB Bridge (0x4000_0000)
    // -------------------------------------------------------------------------
    output wire [31:0] m2_axi_awaddr,
    output wire        m2_axi_awvalid,
    input  wire        m2_axi_awready,
    output wire [31:0] m2_axi_wdata,
    output wire [ 3:0] m2_axi_wstrb,
    output wire        m2_axi_wvalid,
    input  wire        m2_axi_wready,
    input  wire [ 1:0] m2_axi_bresp,
    input  wire        m2_axi_bvalid,
    output wire        m2_axi_bready,
    output wire [31:0] m2_axi_araddr,
    output wire        m2_axi_arvalid,
    input  wire        m2_axi_arready,
    input  wire [31:0] m2_axi_rdata,
    input  wire [ 1:0] m2_axi_rresp,
    input  wire        m2_axi_rvalid,
    output wire        m2_axi_rready
);

    // =========================================================================
    // Decode Logic
    // =========================================================================
    localparam SEL_ERR = 2'd0;
    localparam SEL_ROM = 2'd1;
    localparam SEL_RAM = 2'd2;
    localparam SEL_APB = 2'd3;

    function [1:0] decode;
        input [31:0] addr;
        begin
            if      (addr[31:13] == 19'h0_0000) decode = SEL_ROM;
            else if (addr[31:12] == 20'h0_0010)  decode = SEL_RAM;
            else if (addr[31:28] == 4'h4)         decode = SEL_APB;
            else                                  decode = SEL_ERR;
        end
    endfunction

    // Decode combinational — per master, per channel
    wire [1:0] cpu_w_decode = decode(s_axi_awaddr);
    wire [1:0] cpu_r_decode = decode(s_axi_araddr);
    wire [1:0] dma_w_decode = decode(dma_axi_awaddr);
    wire [1:0] dma_r_decode = decode(dma_axi_araddr);

    // Latched decode — chốt trong IDLE cùng lúc set w_master/r_master
    // Dùng cho w_sel_mux/r_sel_mux → ổn định suốt toàn bộ transaction
    reg [1:0] w_decode_latched;
    reg [1:0] r_decode_latched;

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam W_IDLE     = 3'd0;
    localparam W_AW_WAIT  = 3'd1;
    localparam W_FORWARD  = 3'd2;
    localparam W_ERR_AW   = 3'd3;
    localparam W_ERR_W    = 3'd4;
    localparam W_ERR_RESP = 3'd5;

    localparam R_IDLE     = 3'd0;
    localparam R_AR_WAIT  = 3'd1;
    localparam R_FORWARD  = 3'd2;
    localparam R_ERR_AR   = 3'd3;
    localparam R_ERR_RESP = 3'd4;

    reg [2:0] w_state;
    reg [2:0] r_state;
    reg [1:0] w_sel;
    reg [1:0] r_sel;
    reg       w_master; // 0=CPU, 1=DMA
    reg       r_master; // 0=CPU, 1=DMA

    reg err_awready_r;
    reg err_wready_r;
    reg err_bvalid_r;
    reg err_arready_r;
    reg err_rvalid_r;

    // =========================================================================
    // Input Mux — active master signals
    // =========================================================================
    wire [31:0] mst_awaddr  = w_master ? dma_axi_awaddr  : s_axi_awaddr;
    wire        mst_awvalid = w_master ? dma_axi_awvalid : s_axi_awvalid;
    wire [31:0] mst_wdata   = w_master ? dma_axi_wdata   : s_axi_wdata;
    wire [ 3:0] mst_wstrb   = w_master ? dma_axi_wstrb   : s_axi_wstrb;
    wire        mst_wvalid  = w_master ? dma_axi_wvalid  : s_axi_wvalid;
    wire        mst_bready  = w_master ? dma_axi_bready  : s_axi_bready;
    wire [31:0] mst_araddr  = r_master ? dma_axi_araddr  : s_axi_araddr;
    wire        mst_arvalid = r_master ? dma_axi_arvalid : s_axi_arvalid;
    wire        mst_rready  = r_master ? dma_axi_rready  : s_axi_rready;

    // =========================================================================
    // WRITE FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!resetn) begin
            w_state       <= W_IDLE;
            w_sel         <= SEL_ERR;
            w_master        <= 1'b0;
            w_decode_latched<= SEL_ERR;
            err_awready_r   <= 1'b0;
            err_wready_r    <= 1'b0;
            err_bvalid_r    <= 1'b0;
        end else begin
            err_awready_r <= 1'b0;
            err_wready_r  <= 1'b0;

            case (w_state)

                W_IDLE: begin
                    err_bvalid_r <= 1'b0;
                    if (s_axi_awvalid) begin                    // CPU — higher priority
                        w_master         <= 1'b0;
                        w_decode_latched <= cpu_w_decode;
                        if (cpu_w_decode == SEL_RAM || cpu_w_decode == SEL_APB)
                            w_state <= W_AW_WAIT;
                        else
                            w_state <= W_ERR_AW;
                    end else if (dma_axi_awvalid) begin         // DMA — lower priority
                        w_master         <= 1'b1;
                        w_decode_latched <= dma_w_decode;
                        if (dma_w_decode == SEL_RAM)            // DMA restricted to RAM
                            w_state <= W_AW_WAIT;
                        else
                            w_state <= W_ERR_AW;
                    end
                end

                W_AW_WAIT: begin
                    if (mst_awvalid && ic_awready) begin
                        w_sel   <= w_decode_latched;
                        w_state <= W_FORWARD;
                    end
                end

                W_FORWARD: begin
                    if (ic_bvalid && mst_bready)
                        w_state <= W_IDLE;
                end

                W_ERR_AW: begin
                    err_awready_r <= 1'b1;
                    w_state <= W_ERR_W;
                end

                W_ERR_W: begin
                    if (mst_wvalid) begin
                        err_wready_r <= 1'b1;
                        w_state <= W_ERR_RESP;
                    end
                end

                W_ERR_RESP: begin
                    err_bvalid_r <= 1'b1;
                    if (mst_bready) begin
                        err_bvalid_r <= 1'b0;
                        w_state <= W_IDLE;
                    end
                end

                default: w_state <= W_IDLE;
            endcase
        end
    end

    // =========================================================================
    // READ FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!resetn) begin
            r_state       <= R_IDLE;
            r_sel         <= SEL_ERR;
            r_master        <= 1'b0;
            r_decode_latched<= SEL_ERR;
            err_arready_r   <= 1'b0;
            err_rvalid_r    <= 1'b0;
        end else begin
            err_arready_r <= 1'b0;

            case (r_state)

                R_IDLE: begin
                    err_rvalid_r <= 1'b0;
                    if (s_axi_arvalid) begin                    // CPU — higher priority
                        r_master         <= 1'b0;
                        r_decode_latched <= cpu_r_decode;
                        if (cpu_r_decode != SEL_ERR)
                            r_state <= R_AR_WAIT;
                        else
                            r_state <= R_ERR_AR;
                    end else if (dma_axi_arvalid) begin         // DMA — lower priority
                        r_master         <= 1'b1;
                        r_decode_latched <= dma_r_decode;
                        if (dma_r_decode == SEL_RAM)            // DMA restricted to RAM
                            r_state <= R_AR_WAIT;
                        else
                            r_state <= R_ERR_AR;
                    end
                end

                R_AR_WAIT: begin
                    if (mst_arvalid && ic_arready) begin
                        r_sel   <= r_decode_latched;
                        r_state <= R_FORWARD;
                    end
                end

                R_FORWARD: begin
                    if (ic_rvalid && mst_rready)
                        r_state <= R_IDLE;
                end

                R_ERR_AR: begin
                    err_arready_r <= 1'b1;
                    r_state <= R_ERR_RESP;
                end

                R_ERR_RESP: begin
                    err_rvalid_r <= 1'b1;
                    if (mst_rready) begin
                        err_rvalid_r <= 1'b0;
                        r_state <= R_IDLE;
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Forward flags
    // =========================================================================
    wire w_fwd_aw = (w_state == W_AW_WAIT) || (w_state == W_FORWARD);
    wire w_fwd    = (w_state == W_FORWARD);
    wire r_fwd_ar = (r_state == R_AR_WAIT) || (r_state == R_FORWARD);
    wire r_fwd    = (r_state == R_FORWARD);

    wire [1:0] w_sel_mux = w_fwd ? w_sel : w_decode_latched;
    wire [1:0] r_sel_mux = r_fwd ? r_sel : r_decode_latched;

    // =========================================================================
    // Interconnect internal signals (before demux to masters)
    // =========================================================================
    wire ic_awready = w_fwd_aw ? ((w_sel_mux == SEL_RAM) ? m1_axi_awready : m2_axi_awready)
                               : err_awready_r;

    wire ic_wready  = w_fwd   ? ((w_sel == SEL_RAM) ? m1_axi_wready : m2_axi_wready)
                               : err_wready_r;

    wire ic_bvalid  = w_fwd   ? ((w_sel == SEL_RAM) ? m1_axi_bvalid : m2_axi_bvalid)
                               : err_bvalid_r;

    wire [1:0] ic_bresp = w_fwd ? ((w_sel == SEL_RAM) ? m1_axi_bresp : m2_axi_bresp) : 2'b11;

    wire ic_arready = r_fwd_ar ? ((r_sel_mux == SEL_ROM) ? m0_axi_arready :
                                  (r_sel_mux == SEL_RAM)  ? m1_axi_arready : m2_axi_arready)
                               : err_arready_r;

    wire ic_rvalid  = r_fwd   ? ((r_sel == SEL_ROM) ? m0_axi_rvalid :
                                  (r_sel == SEL_RAM) ? m1_axi_rvalid : m2_axi_rvalid)
                               : err_rvalid_r;

    wire [31:0] ic_rdata = r_fwd ? ((r_sel == SEL_ROM) ? m0_axi_rdata :
                                    (r_sel == SEL_RAM)  ? m1_axi_rdata : m2_axi_rdata) : 32'h0;

    wire [1:0] ic_rresp = r_fwd ? (
                              (r_sel == SEL_ROM) ? m0_axi_rresp :
                              (r_sel == SEL_RAM) ? m1_axi_rresp :
                                                   m2_axi_rresp
                          ) : 2'b11;

    // =========================================================================
    // Owner flags — chỉ active khi bus thực sự đang được dùng (state != IDLE)
    // Tránh w_master/r_master stale khi vừa về IDLE → không spurious ready
    // =========================================================================
    wire w_cpu_owner = (w_state != W_IDLE) && (w_master == 1'b0);
    wire w_dma_owner = (w_state != W_IDLE) && (w_master == 1'b1);
    wire r_cpu_owner = (r_state != R_IDLE) && (r_master == 1'b0);
    wire r_dma_owner = (r_state != R_IDLE) && (r_master == 1'b1);

    // =========================================================================
    // Demux responses → correct master
    // =========================================================================
    // --- CPU ---
    assign s_axi_awready = w_cpu_owner ? ic_awready : 1'b0;
    assign s_axi_wready  = w_cpu_owner ? ic_wready  : 1'b0;
    assign s_axi_bvalid  = w_cpu_owner ? ic_bvalid  : 1'b0;
    assign s_axi_bresp   = w_cpu_owner ? ic_bresp   : 2'b11;
    assign s_axi_arready = r_cpu_owner ? ic_arready : 1'b0;
    assign s_axi_rvalid  = r_cpu_owner ? ic_rvalid  : 1'b0;
    assign s_axi_rdata   = r_cpu_owner ? ic_rdata   : 32'h0;
    assign s_axi_rresp   = r_cpu_owner ? ic_rresp   : 2'b11;

    // --- DMA ---
    assign dma_axi_awready = w_dma_owner ? ic_awready : 1'b0;
    assign dma_axi_wready  = w_dma_owner ? ic_wready  : 1'b0;
    assign dma_axi_bvalid  = w_dma_owner ? ic_bvalid  : 1'b0;
    assign dma_axi_bresp   = w_dma_owner ? ic_bresp   : 2'b11;
    assign dma_axi_arready = r_dma_owner ? ic_arready : 1'b0;
    assign dma_axi_rvalid  = r_dma_owner ? ic_rvalid  : 1'b0;
    assign dma_axi_rdata   = r_dma_owner ? ic_rdata   : 32'h0;
    assign dma_axi_rresp   = r_dma_owner ? ic_rresp   : 2'b11;

    // =========================================================================
    // Slave-side output wiring (dùng mst_* thay s_axi_* trực tiếp)
    // =========================================================================

    // --- Slave 0: ROM (Read Only) ---
    assign m0_axi_araddr  = mst_araddr;
    assign m0_axi_arvalid = r_fwd_ar && (r_sel_mux == SEL_ROM) ? mst_arvalid : 1'b0;
    assign m0_axi_rready  = r_fwd    && (r_sel     == SEL_ROM) ? mst_rready  : 1'b0;

    // --- Slave 1: RAM ---
    assign m1_axi_awaddr  = mst_awaddr;
    assign m1_axi_awvalid = w_fwd_aw && (w_sel_mux == SEL_RAM) ? mst_awvalid : 1'b0;
    assign m1_axi_wdata   = mst_wdata;
    assign m1_axi_wstrb   = mst_wstrb;
    assign m1_axi_wvalid  = w_fwd    && (w_sel     == SEL_RAM) ? mst_wvalid  : 1'b0;
    assign m1_axi_bready  = w_fwd    && (w_sel     == SEL_RAM) ? mst_bready  : 1'b0;
    assign m1_axi_araddr  = mst_araddr;
    assign m1_axi_arvalid = r_fwd_ar && (r_sel_mux == SEL_RAM) ? mst_arvalid : 1'b0;
    assign m1_axi_rready  = r_fwd    && (r_sel     == SEL_RAM) ? mst_rready  : 1'b0;

    // --- Slave 2: APB Bridge ---
    assign m2_axi_awaddr  = mst_awaddr;
    assign m2_axi_awvalid = w_fwd_aw && (w_sel_mux == SEL_APB) ? mst_awvalid : 1'b0;
    assign m2_axi_wdata   = mst_wdata;
    assign m2_axi_wstrb   = mst_wstrb;
    assign m2_axi_wvalid  = w_fwd    && (w_sel     == SEL_APB) ? mst_wvalid  : 1'b0;
    assign m2_axi_bready  = w_fwd    && (w_sel     == SEL_APB) ? mst_bready  : 1'b0;
    assign m2_axi_araddr  = mst_araddr;
    assign m2_axi_arvalid = r_fwd_ar && (r_sel_mux == SEL_APB) ? mst_arvalid : 1'b0;
    assign m2_axi_rready  = r_fwd    && (r_sel     == SEL_APB) ? mst_rready  : 1'b0;

endmodule
