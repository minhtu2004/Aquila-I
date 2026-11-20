`timescale 1ns / 1ps
// =============================================================================
// ram.v — AXI4-Lite RAM wrapper cho sky130_sram_2kbyte_1rw1r_32x512_8
// -----------------------------------------------------------------------------
// Base Address : 0x0001_0000
// Size         : 2KB (512 x 32-bit words)
// Read Latency : 2 cycle (1 cycle SRAM latch + 1 cycle dout stable)
// Write        : byte-enable via wmask0, response sau 1 cycle
// Port 0       : RW — dùng cho tất cả access
// Port 1       : R  — tie off (csb1=1)
//
// FSM:
//   IDLE       → nhận AW/W (riêng biệt như cũ) hoặc AR
//   WRITE_REQ  → drive SRAM write 1 cycle → WRITE_RESP
//   WRITE_RESP → assert BVALID → IDLE
//   READ_REQ   → drive SRAM read 1 cycle (csb0=0, web0=1)
//   READ_WAIT  → latch dout0 trước khi SRAM model quăng X
//   READ_RESP  → assert RVALID/RDATA → IDLE
// =============================================================================
module ram (
    input  wire        clk,
    input  wire        resetn,

    // Write Address Channel
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,

    // Write Data Channel
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,

    // Write Response Channel
    output reg  [ 1:0] s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    // Read Address Channel
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,

    // Read Data Channel
    output reg  [31:0] s_axi_rdata,
    output reg  [ 1:0] s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    // =========================================================================
    // FSM states
    // =========================================================================
    localparam [2:0]
        S_IDLE            = 3'd0,
        S_WRITE_REQ       = 3'd1,
        S_WRITE_RESP      = 3'd2,
        S_WRITE_RESP_WAIT = 3'd3,
        S_READ_REQ        = 3'd4,
        S_READ_WAIT       = 3'd5,
        S_READ_RESP       = 3'd6,
        S_READ_RESP_WAIT  = 3'd7;

    reg [2:0] state;

    // =========================================================================
    // AW / W latch
    // =========================================================================
    reg        aw_active;
    reg [31:0] aw_addr_lat;
    reg        w_active;
    reg [31:0] w_data_lat;
    reg [ 3:0] w_strb_lat;

    // =========================================================================
    // AR latch
    // =========================================================================
    reg [31:0] ar_addr_lat;

    // =========================================================================
    // Read data latch — bắt dout0 trước khi SRAM model set lại X
    // =========================================================================
    reg [31:0] read_data_lat;

    // =========================================================================
    // SRAM port 0 signals
    // =========================================================================
    reg        sram_csb0;
    reg        sram_web0;
    reg [ 3:0] sram_wmask0;
    reg [ 8:0] sram_addr0;
    reg [31:0] sram_din0;
    wire [31:0] sram_dout0;

    // =========================================================================
    // SRAM instance
    // =========================================================================
    sky130_sram_2kbyte_1rw1r_32x512_8 #(
        .VERBOSE(0)
    ) u_sram (
        .clk0  (clk),
        .csb0  (sram_csb0),
        .web0  (sram_web0),
        .wmask0(sram_wmask0),
        .addr0 (sram_addr0),
        .din0  (sram_din0),
        .dout0 (sram_dout0),
        // Port 1: tie off
        .clk1  (clk),
        .csb1  (1'b1),
        .addr1 (9'b0),
        .dout1 ()
    );

    // =========================================================================
    // Default SRAM: disabled
    // =========================================================================
    always @(*) begin
        sram_csb0   = 1'b1;
        sram_web0   = 1'b1;
        sram_wmask0 = 4'b0;
        sram_addr0  = 9'b0;
        sram_din0   = 32'b0;

        case (state)
            S_WRITE_REQ: begin
                sram_csb0   = 1'b0;
                sram_web0   = 1'b0;
                sram_wmask0 = w_strb_lat;
                sram_addr0  = aw_addr_lat[10:2];
                sram_din0   = w_data_lat;
            end
            S_READ_REQ: begin
                sram_csb0   = 1'b0;
                sram_web0   = 1'b1;
                sram_wmask0 = 4'b0;
                sram_addr0  = ar_addr_lat[10:2];
                sram_din0   = 32'b0;
            end
            default: ;
        endcase
    end

    // =========================================================================
    // AW / W latch logic
    // =========================================================================
    always @(posedge clk) begin
        if (!resetn) begin
            aw_active     <= 1'b0;
            aw_addr_lat   <= 32'b0;
            w_active      <= 1'b0;
            w_data_lat    <= 32'b0;
            w_strb_lat    <= 4'b0;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;

            if (state == S_WRITE_REQ) begin
                aw_active <= 1'b0;
                w_active  <= 1'b0;
            end

            if (s_axi_awvalid && !aw_active && (state == S_IDLE)) begin
                aw_addr_lat   <= s_axi_awaddr;
                aw_active     <= 1'b1;
                s_axi_awready <= 1'b1;
            end

            if (s_axi_wvalid && !w_active && (state == S_IDLE)) begin
                w_data_lat   <= s_axi_wdata;
                w_strb_lat   <= s_axi_wstrb;
                w_active     <= 1'b1;
                s_axi_wready <= 1'b1;
            end
        end
    end

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!resetn) begin
            state         <= S_IDLE;
            ar_addr_lat   <= 32'b0;
            read_data_lat <= 32'b0;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'b0;
            s_axi_rresp   <= 2'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b0;
        end else begin
            s_axi_arready <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (aw_active && w_active) begin
                        state <= S_WRITE_REQ;
                    end else if (s_axi_arvalid && !aw_active && !w_active) begin
                        ar_addr_lat   <= s_axi_araddr;
                        s_axi_arready <= 1'b1;
                        state         <= S_READ_REQ;
                    end
                end

                S_WRITE_REQ: begin
                    `ifdef SIMULATION
                   // $display("[%0t] SRAM_WR addr=0x%08x idx=0x%03x data=0x%08x wstrb=%b",
                            // $time, aw_addr_lat, aw_addr_lat[10:2], w_data_lat, w_strb_lat);
                    `endif
                    state <= S_WRITE_RESP;
                end

                S_WRITE_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;
                    state        <= S_WRITE_RESP_WAIT;
                end

                S_WRITE_RESP_WAIT: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                S_READ_REQ: begin
                    `ifdef SIMULATION
                    //$display("[%0t] SRAM_RD_REQ addr=0x%08x idx=0x%03x",
                    //         $time, ar_addr_lat, ar_addr_lat[10:2]);
                    `endif
                    state <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    // Latch dout0 ngay tại posedge này — trước khi SRAM model
                    // chạy #T_HOLD và set dout0 = X ở cuối cycle
                    `ifdef SIMULATION
                   // $display("[%0t] SRAM_RD_CAPTURE addr=0x%08x idx=0x%03x data=0x%08x",
                     //        $time, ar_addr_lat, ar_addr_lat[10:2], sram_dout0);
                    `endif
                    read_data_lat <= sram_dout0;
                    state         <= S_READ_RESP;
                end

                S_READ_RESP: begin
                    `ifdef SIMULATION
                   // $display("[%0t] SRAM_RD_RESP addr=0x%08x idx=0x%03x data=0x%08x",
                     //        $time, ar_addr_lat, ar_addr_lat[10:2], read_data_lat);
                    `endif
                    s_axi_rdata  <= read_data_lat;
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    state        <= S_READ_RESP_WAIT;
                end

                S_READ_RESP_WAIT: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
