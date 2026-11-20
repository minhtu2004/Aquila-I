// =============================================================================
// crc32_core.v — CRC-32 bit-serial, 32 cycles/word
//
// Spec:
//   Polynomial : 0xEDB88320 (LSB-first, Ethernet/standard)
//   Init       : 0xFFFFFFFF
//   Final XOR  : 0xFFFFFFFF
//
// Interface:
//   - crc_start  : pulse 1 cycle to reset CRC state (load init)
//   - in_valid / in_ready : FIFO pop handshake
//   - in_data [31:0], in_last
//   - result_valid : asserted when crc_result is ready (after last word)
//   - result [31:0] : final CRC (after XOR)
// =============================================================================
module crc32_core (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        crc_start,   // pulse: reset CRC, begin new stream

    // input from FIFO
    output reg         in_ready,
    input  wire        in_valid,
    input  wire [31:0] in_data,
    input  wire        in_last,

    // output
    output reg         result_valid,
    output reg  [31:0] result
);
    localparam POLY = 32'hEDB88320;
    localparam INIT = 32'hFFFFFFFF;

    // FSM
    localparam S_IDLE    = 2'd0;
    localparam S_FETCH   = 2'd1;   // wait for FIFO valid, latch word
    localparam S_COMPUTE = 2'd2;   // 32 bit-serial cycles
    localparam S_RESULT  = 2'd3;

    reg [1:0]  state;
    reg [31:0] crc_reg;     // running CRC
    reg [31:0] shift_reg;   // word being processed
    reg [4:0]  bit_cnt;     // 0-31
    reg        last_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            crc_reg      <= INIT;
            shift_reg    <= 0;
            bit_cnt      <= 0;
            last_latch   <= 0;
            in_ready     <= 0;
            result_valid <= 0;
            result       <= 0;
        end else begin
            result_valid <= 1'b0;  // default

            // crc_start resets state any time
            if (crc_start) begin
                crc_reg      <= INIT;
                shift_reg    <= 32'd0;
                bit_cnt      <= 5'd0;
                last_latch   <= 1'b0;
                result_valid <= 1'b0;
                state        <= S_FETCH;
                in_ready     <= 1'b1;
            end else begin
                case (state)

                    S_IDLE: begin
                        in_ready <= 1'b0;
                    end

                    S_FETCH: begin
                        in_ready <= 1'b1;
                        if (in_valid & in_ready) begin
                            shift_reg  <= in_data;
                            last_latch <= in_last;
                            bit_cnt    <= 5'd0;
                            in_ready   <= 1'b0;
                            state      <= S_COMPUTE;
                        end
                    end

                    S_COMPUTE: begin
                        // LSB-first CRC-32
                        if (crc_reg[0] ^ shift_reg[0])
                            crc_reg <= {1'b0, crc_reg[31:1]} ^ POLY;
                        else
                            crc_reg <= {1'b0, crc_reg[31:1]};
                        shift_reg <= {1'b0, shift_reg[31:1]};
                        bit_cnt   <= bit_cnt + 1'b1;

                        if (bit_cnt == 5'd31) begin
                            if (last_latch) begin
                                state <= S_RESULT;
                            end else begin
                                state    <= S_FETCH;
                                in_ready <= 1'b1;
                            end
                        end
                    end

                    S_RESULT: begin
                        result       <= crc_reg ^ INIT;  // final XOR 0xFFFFFFFF
                        result_valid <= 1'b1;
                        state        <= S_IDLE;
                    end

                endcase
            end
        end
    end
endmodule
