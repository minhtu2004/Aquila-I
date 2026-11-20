`timescale 1ns / 1ps
// =============================================================================
// axi_to_apb_bridge.v — AXI4-Lite to APB Bridge
// -----------------------------------------------------------------------------
// AXI4-Lite Slave → APB Master
// Tuần tự: 1 transaction tại 1 thời điểm (write hoặc read, không overlap)
// -----------------------------------------------------------------------------
// APB Protocol:
//   SETUP  : PSEL=1, PENABLE=0 — 1 cycle cố định
//   ACCESS : PSEL=1, PENABLE=1 — stall theo PREADY
// -----------------------------------------------------------------------------
// Address offset:
//   PADDR = axi_addr - APB_BASE
// =============================================================================
module axi_to_apb_bridge #(
    parameter APB_BASE = 32'h4000_0000
)(
    input  wire        clk,
    input  wire        resetn,

    // -------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (từ AXI Interconnect)
    // -------------------------------------------------------------------------
    // Write Address Channel
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,   // wire — combinational
    // Write Data Channel
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,    // wire — combinational
    // Write Response Channel
    output reg  [ 1:0] s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // Read Address Channel
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,   // wire — combinational
    // Read Data Channel
    output reg  [31:0] s_axi_rdata,
    output reg  [ 1:0] s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // -------------------------------------------------------------------------
    // APB Master Interface (xuống apb_interconnect)
    // -------------------------------------------------------------------------
    output reg  [31:0] M_PADDR,
    output reg         M_PSEL,
    output reg         M_PENABLE,
    output reg         M_PWRITE,
    output reg  [31:0] M_PWDATA,
    input  wire [31:0] M_PRDATA,
    input  wire        M_PREADY,
    input  wire        M_PSLVERR
);

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam IDLE   = 3'd0;
    localparam SETUP  = 3'd1; // PSEL=1, PENABLE=0 — 1 cycle
    localparam ACCESS = 3'd2; // PSEL=1, PENABLE=1 — chờ PREADY
    localparam W_RESP = 3'd3; // trả bvalid về AXI
    localparam R_RESP = 3'd4; // trả rvalid/rdata về AXI

    reg [2:0] state;
    reg       is_write; // 1=write transaction, 0=read transaction

    // =========================================================================
    // AW / W / AR Latch
    // =========================================================================
    reg [31:0] aw_addr_lat;
    reg        aw_active;

    reg [31:0] w_data_lat;
    reg [ 3:0] w_strb_lat;
    reg        w_active;

    reg [31:0] ar_addr_lat;
    reg        ar_active;

    // -------------------------------------------------------------------------
    // READY — combinational, sync với VALID
    // Chỉ nhận khi IDLE và chưa latch channel đó
    // -------------------------------------------------------------------------
    assign s_axi_awready = (state == IDLE) && !aw_active && s_axi_awvalid;
    assign s_axi_wready  = (state == IDLE) && !w_active  && s_axi_wvalid;
    assign s_axi_arready = (state == IDLE) && !ar_active  && s_axi_arvalid;

    // -------------------------------------------------------------------------
    // Latch AW
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            aw_addr_lat <= 32'h0;
            aw_active   <= 1'b0;
        end else begin
            // Latch khi handshake
            if (s_axi_awvalid && s_axi_awready) begin
                aw_addr_lat <= s_axi_awaddr;
                aw_active   <= 1'b1;
            end
            // Clear sau khi vào SETUP (write)
            if (state == SETUP && is_write)
                aw_active <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Latch W
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            w_data_lat <= 32'h0;
            w_strb_lat <= 4'h0;
            w_active   <= 1'b0;
        end else begin
            if (s_axi_wvalid && s_axi_wready) begin
                w_data_lat <= s_axi_wdata;
                w_strb_lat <= s_axi_wstrb;
                w_active   <= 1'b1;
            end
            if (state == SETUP && is_write)
                w_active <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Latch AR
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            ar_addr_lat <= 32'h0;
            ar_active   <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                ar_addr_lat <= s_axi_araddr;
                ar_active   <= 1'b1;
            end
            if (state == SETUP && !is_write)
                ar_active <= 1'b0;
        end
    end

    // =========================================================================
    // FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!resetn) begin
            state        <= IDLE;
            is_write     <= 1'b0;
            M_PSEL       <= 1'b0;
            M_PENABLE    <= 1'b0;
            M_PWRITE     <= 1'b0;
            M_PADDR      <= 32'h0;
            M_PWDATA     <= 32'h0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'h0;
            s_axi_rresp  <= 2'b00;
        end else begin
            case (state)

                // -------------------------------------------------------------
                // IDLE: chờ transaction
                // Write ưu tiên — chỉ nhận read khi không có write pending
                // -------------------------------------------------------------
                IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    s_axi_rvalid <= 1'b0;
                    M_PSEL       <= 1'b0;
                    M_PENABLE    <= 1'b0;

                    if (aw_active && w_active) begin
                        // Write: cả AW và W đã latch
                        is_write  <= 1'b1;
                        state     <= SETUP;
                        M_PADDR   <= aw_addr_lat;
                        M_PWRITE  <= 1'b1;
                        M_PWDATA  <= w_data_lat;
                        M_PSEL    <= 1'b1;
                        M_PENABLE <= 1'b0;
                    end else if (ar_active && !aw_active && !w_active) begin
                        // Read: chỉ khi không có write pending
                        is_write  <= 1'b0;
                        state     <= SETUP;
                        M_PADDR   <= ar_addr_lat;
                        M_PWRITE  <= 1'b0;
                        M_PWDATA  <= 32'h0;
                        M_PSEL    <= 1'b1;
                        M_PENABLE <= 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // SETUP: PSEL=1, PENABLE=0 — cố định 1 cycle
                // APB signals đã drive từ IDLE, giữ nguyên
                // -------------------------------------------------------------
                SETUP: begin
                    M_PENABLE <= 1'b1;
                    state     <= ACCESS;
                end

                // -------------------------------------------------------------
                // ACCESS: PSEL=1, PENABLE=1 — stall cho đến khi PREADY=1
                // PREADY=0: giữ nguyên toàn bộ APB signals
                // -------------------------------------------------------------
                ACCESS: begin
                    if (M_PREADY) begin
                        M_PSEL    <= 1'b0;
                        M_PENABLE <= 1'b0;
                        if (is_write) begin
                            s_axi_bresp  <= M_PSLVERR ? 2'b10 : 2'b00;
                            s_axi_bvalid <= 1'b1;
                            state        <= W_RESP;
                        end else begin
                            s_axi_rdata  <= M_PRDATA;
                            s_axi_rresp  <= M_PSLVERR ? 2'b10 : 2'b00;
                            s_axi_rvalid <= 1'b1;
                            state        <= R_RESP;
                        end
                    end
                end

                // -------------------------------------------------------------
                // W_RESP: giữ bvalid đến khi bready
                // -------------------------------------------------------------
                W_RESP: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        state        <= IDLE;
                    end
                end

                // -------------------------------------------------------------
                // R_RESP: giữ rvalid đến khi rready
                // -------------------------------------------------------------
                R_RESP: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        state        <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
