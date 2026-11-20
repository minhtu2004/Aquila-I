// =============================================================================
// aes_core.v — AES-128 encrypt, iterative (1 round per clock)
//
// Phase-1 timing optimisation: incremental key schedule
//   - Removed combinational aes_key_expand (11 round keys chained from key_reg)
//   - Added round_key_reg: stores current round key as a register
//   - next_round_key computed each cycle from round_key_reg only
//     (1x SubWord + Rcon + XOR — no chain, no mux)
//   - Latency unchanged: 12 cycles after start
//   - Interface unchanged: start/plaintext/key/done/ciphertext/busy
//
// Cycle map:
//   cycle 0  : latch key_reg, plaintext → round_key_reg = key (= round_key_0)
//   cycle 1  : AddRoundKey(state, round_key_reg[0])
//              round_key_reg advances to round_key_1
//   cycles 2-10: rounds 1-9
//   cycle 11 : round 10 (no MixColumns), done
// =============================================================================
module aes_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,
    output reg          done,
    output reg  [127:0] ciphertext,
    output wire         busy
);

    // =========================================================================
    // State & control registers
    // =========================================================================
    reg [127:0] state;
    reg [3:0]   round;
    reg         running;

    assign busy = running;

    // =========================================================================
    // Incremental key schedule
    //   round_key_reg holds the round key used THIS cycle.
    //   next_round_key is computed combinationally from round_key_reg
    //   using only 4 S-box lookups (SubWord) + Rcon + XOR — single level,
    //   no chaining.
    // =========================================================================
    reg  [127:0] round_key_reg;

    // Rcon lookup table — index 1..10, Yosys-safe (no dynamic loop)
    function [7:0] rcon_byte;
        input [3:0] r;
        begin
            case (r)
                4'd1:    rcon_byte = 8'h01;
                4'd2:    rcon_byte = 8'h02;
                4'd3:    rcon_byte = 8'h04;
                4'd4:    rcon_byte = 8'h08;
                4'd5:    rcon_byte = 8'h10;
                4'd6:    rcon_byte = 8'h20;
                4'd7:    rcon_byte = 8'h40;
                4'd8:    rcon_byte = 8'h80;
                4'd9:    rcon_byte = 8'h1b;
                4'd10:   rcon_byte = 8'h36;
                default: rcon_byte = 8'h00;
            endcase
        end
    endfunction

    // SubWord: 4 S-box lookups on the last word of round_key_reg
    wire [7:0] sw_b0, sw_b1, sw_b2, sw_b3;
    // RotWord then SubWord on W[last] = round_key_reg[31:0]
    aes_sbox u_sw0 (.in(round_key_reg[23:16]), .out(sw_b0));  // rotate: byte1
    aes_sbox u_sw1 (.in(round_key_reg[15: 8]), .out(sw_b1));  // rotate: byte2
    aes_sbox u_sw2 (.in(round_key_reg[ 7: 0]), .out(sw_b2));  // rotate: byte3
    aes_sbox u_sw3 (.in(round_key_reg[31:24]), .out(sw_b3));  // rotate: byte0

    // next round index = round + 1 (used for Rcon lookup)
    wire [3:0] next_round = round + 4'd1;

    // SubWord ^ Rcon applied to W[4k] derivation
    wire [31:0] subword_rcon = {sw_b0 ^ rcon_byte(next_round), sw_b1, sw_b2, sw_b3};

    // Four new words
    wire [31:0] nw0 = round_key_reg[127:96] ^ subword_rcon;
    wire [31:0] nw1 = round_key_reg[ 95:64] ^ nw0;
    wire [31:0] nw2 = round_key_reg[ 63:32] ^ nw1;
    wire [31:0] nw3 = round_key_reg[ 31: 0] ^ nw2;

    wire [127:0] next_round_key = {nw0, nw1, nw2, nw3};

    // =========================================================================
    // SubBytes — 16 parallel S-box instances (unchanged)
    // =========================================================================
    wire [7:0] sb_out [0:15];
    genvar b;
    generate
        for (b = 0; b < 16; b = b + 1) begin : sub_bytes
            aes_sbox u_sb (.in(state[127 - 8*b -: 8]), .out(sb_out[b]));
        end
    endgenerate

    wire [127:0] after_subbytes;
    genvar sb;
    generate
        for (sb = 0; sb < 16; sb = sb + 1) begin : pack_sb
            assign after_subbytes[127 - 8*sb -: 8] = sb_out[sb];
        end
    endgenerate

    // =========================================================================
    // ShiftRows (unchanged)
    // =========================================================================
    function [127:0] shift_rows;
        input [127:0] s;
        reg [7:0] m [0:15];
        reg [7:0] o [0:15];
        integer k;
        begin
            for (k = 0; k < 16; k = k + 1)
                m[k] = s[127 - 8*k -: 8];
            o[0]  = m[0];  o[4]  = m[4];  o[8]  = m[8];  o[12] = m[12];
            o[1]  = m[5];  o[5]  = m[9];  o[9]  = m[13]; o[13] = m[1];
            o[2]  = m[10]; o[6]  = m[14]; o[10] = m[2];  o[14] = m[6];
            o[3]  = m[15]; o[7]  = m[3];  o[11] = m[7];  o[15] = m[11];
            shift_rows = {o[0],  o[1],  o[2],  o[3],
                          o[4],  o[5],  o[6],  o[7],
                          o[8],  o[9],  o[10], o[11],
                          o[12], o[13], o[14], o[15]};
        end
    endfunction

    wire [127:0] after_shiftrows = shift_rows(after_subbytes);

    // =========================================================================
    // MixColumns (unchanged)
    // =========================================================================
    function [7:0] xtime;
        input [7:0] a;
        begin xtime = a[7] ? ((a << 1) ^ 8'h1b) : (a << 1); end
    endfunction

    function [127:0] mix_columns;
        input [127:0] s;
        reg [7:0] a0, a1, a2, a3, r0, r1, r2, r3;
        integer col;
        reg [127:0] out;
        begin
            out = 128'b0;
            for (col = 0; col < 4; col = col + 1) begin
                a0 = s[127 - 32*col -: 8];
                a1 = s[119 - 32*col -: 8];
                a2 = s[111 - 32*col -: 8];
                a3 = s[103 - 32*col -: 8];
                r0 = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2               ^ a3;
                r1 = a0        ^ xtime(a1)         ^ (xtime(a2) ^ a2) ^ a3;
                r2 = a0        ^ a1                ^ xtime(a2)        ^ (xtime(a3) ^ a3);
                r3 = (xtime(a0) ^ a0) ^ a1         ^ a2               ^ xtime(a3);
                out[127 - 32*col -: 8] = r0;
                out[119 - 32*col -: 8] = r1;
                out[111 - 32*col -: 8] = r2;
                out[103 - 32*col -: 8] = r3;
            end
            mix_columns = out;
        end
    endfunction

    wire [127:0] after_mixcols = mix_columns(after_shiftrows);

    // =========================================================================
    // FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= 128'd0;
            round         <= 4'd0;
            running       <= 1'b0;
            done          <= 1'b0;
            ciphertext    <= 128'd0;
            round_key_reg <= 128'd0;
        end else begin
            done <= 1'b0;

            if (start && !running) begin
                // Cycle 0: latch key as round_key_reg (= round_key_0), latch plaintext
                round_key_reg <= key;
                state         <= plaintext;
                round         <= 4'd0;
                running       <= 1'b1;

            end else if (running) begin
                if (round == 4'd0) begin
                    // Cycle 1: AddRoundKey with round_key_0
                    state         <= state ^ round_key_reg;
                    round_key_reg <= next_round_key;   // advance to round_key_1
                    round         <= 4'd1;

                end else if (round < 4'd10) begin
                    // Rounds 1-9: Sub + Shift + Mix + AddRoundKey
                    state         <= after_mixcols ^ round_key_reg;
                    round_key_reg <= next_round_key;
                    round         <= round + 4'd1;

                end else begin
                    // Round 10: Sub + Shift + AddRoundKey (no MixColumns)
                    ciphertext <= after_shiftrows ^ round_key_reg;
                    done       <= 1'b1;
                    running    <= 1'b0;
                    round      <= 4'd0;
                end
            end
        end
    end

endmodule
