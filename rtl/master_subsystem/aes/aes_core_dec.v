// =============================================================================
// aes_core_dec.v — AES-128 decrypt, iterative, backward key schedule
// (v2 — see chat: removes rk[0:10] register file and variable-index mux tree)
// =============================================================================
module aes_core_dec (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] ciphertext,
    input  wire [127:0] key,
    output reg          done,
    output reg  [127:0] plaintext,
    output wire         busy
);

    reg [127:0] state;
    reg [127:0] round_key_reg;
    reg [3:0]   round;
    reg         running;
    reg         phase;

    localparam PHASE_KEYGEN  = 1'b0;
    localparam PHASE_DECRYPT = 1'b1;

    assign busy = running;

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

    wire [31:0] curr_w0 = round_key_reg[127:96];
    wire [31:0] curr_w1 = round_key_reg[ 95:64];
    wire [31:0] curr_w2 = round_key_reg[ 63:32];
    wire [31:0] curr_w3 = round_key_reg[ 31: 0];

    wire [31:0] prev_w3_pre = curr_w3 ^ curr_w2;
    wire [31:0] prev_w2_pre = curr_w2 ^ curr_w1;
    wire [31:0] prev_w1_pre = curr_w1 ^ curr_w0;

    wire use_backward_key = (phase == PHASE_DECRYPT);
    wire [31:0] sbox_word = use_backward_key ? prev_w3_pre : curr_w3;

    wire [7:0] sw_b0, sw_b1, sw_b2, sw_b3;
    aes_sbox u_sw0 (.in(sbox_word[23:16]), .out(sw_b0));
    aes_sbox u_sw1 (.in(sbox_word[15: 8]), .out(sw_b1));
    aes_sbox u_sw2 (.in(sbox_word[ 7: 0]), .out(sw_b2));
    aes_sbox u_sw3 (.in(sbox_word[31:24]), .out(sw_b3));

    wire [3:0]  fwd_rcon_idx = round + 4'd1;
    wire [31:0] fwd_subword_rcon = {sw_b0 ^ rcon_byte(fwd_rcon_idx), sw_b1, sw_b2, sw_b3};

    wire [31:0] fwd_w0 = curr_w0 ^ fwd_subword_rcon;
    wire [31:0] fwd_w1 = curr_w1 ^ fwd_w0;
    wire [31:0] fwd_w2 = curr_w2 ^ fwd_w1;
    wire [31:0] fwd_w3 = curr_w3 ^ fwd_w2;

    wire [127:0] next_round_key = {fwd_w0, fwd_w1, fwd_w2, fwd_w3};

    wire [31:0] bwd_subword_rcon = {sw_b0 ^ rcon_byte(round), sw_b1, sw_b2, sw_b3};
    wire [31:0] prev_w0 = curr_w0 ^ bwd_subword_rcon;
    wire [31:0] prev_w1 = prev_w1_pre;
    wire [31:0] prev_w2 = prev_w2_pre;
    wire [31:0] prev_w3 = prev_w3_pre;

    wire [127:0] prev_round_key = {prev_w0, prev_w1, prev_w2, prev_w3};

    wire [7:0] isb_out [0:15];
    genvar b;
    generate
        for (b = 0; b < 16; b = b + 1) begin : inv_sub_bytes
            aes_inv_sbox u_isb (.in(state[127 - 8*b -: 8]), .out(isb_out[b]));
        end
    endgenerate

    wire [127:0] after_invsubbytes;
    genvar sb;
    generate
        for (sb = 0; sb < 16; sb = sb + 1) begin : pack_isb
            assign after_invsubbytes[127 - 8*sb -: 8] = isb_out[sb];
        end
    endgenerate

    function [127:0] inv_shift_rows;
        input [127:0] s;
        reg [7:0] m [0:15];
        reg [7:0] o [0:15];
        integer k;
        begin
            for (k = 0; k < 16; k = k + 1)
                m[k] = s[127 - 8*k -: 8];
            o[0]  = m[0];  o[4]  = m[4];  o[8]  = m[8];  o[12] = m[12];
            o[1]  = m[13]; o[5]  = m[1];  o[9]  = m[5];  o[13] = m[9];
            o[2]  = m[10]; o[6]  = m[14]; o[10] = m[2];  o[14] = m[6];
            o[3]  = m[7];  o[7]  = m[11]; o[11] = m[15]; o[15] = m[3];
            inv_shift_rows = {o[0],  o[1],  o[2],  o[3],
                              o[4],  o[5],  o[6],  o[7],
                              o[8],  o[9],  o[10], o[11],
                              o[12], o[13], o[14], o[15]};
        end
    endfunction

    wire [127:0] after_isr = inv_shift_rows(after_invsubbytes);
    wire [127:0] after_addkey = after_isr ^ round_key_reg;

    function [7:0] xtime;
        input [7:0] a;
        begin xtime = a[7] ? ((a << 1) ^ 8'h1b) : (a << 1); end
    endfunction

    function [7:0] mul9;
        input [7:0] a;
        begin mul9 = xtime(xtime(xtime(a))) ^ a; end
    endfunction
    function [7:0] mul11;
        input [7:0] a;
        begin mul11 = xtime(xtime(xtime(a))) ^ xtime(a) ^ a; end
    endfunction
    function [7:0] mul13;
        input [7:0] a;
        begin mul13 = xtime(xtime(xtime(a))) ^ xtime(xtime(a)) ^ a; end
    endfunction
    function [7:0] mul14;
        input [7:0] a;
        begin mul14 = xtime(xtime(xtime(a))) ^ xtime(xtime(a)) ^ xtime(a); end
    endfunction

    function [127:0] inv_mix_columns;
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
                r0 = mul14(a0) ^ mul11(a1) ^ mul13(a2) ^ mul9(a3);
                r1 = mul9(a0)  ^ mul14(a1) ^ mul11(a2) ^ mul13(a3);
                r2 = mul13(a0) ^ mul9(a1)  ^ mul14(a2) ^ mul11(a3);
                r3 = mul11(a0) ^ mul13(a1) ^ mul9(a2)  ^ mul14(a3);
                out[127 - 32*col -: 8] = r0;
                out[119 - 32*col -: 8] = r1;
                out[111 - 32*col -: 8] = r2;
                out[103 - 32*col -: 8] = r3;
            end
            inv_mix_columns = out;
        end
    endfunction

    wire [127:0] after_invmix = inv_mix_columns(after_addkey);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= 128'd0;
            round_key_reg <= 128'd0;
            round         <= 4'd0;
            running       <= 1'b0;
            phase         <= PHASE_KEYGEN;
            done          <= 1'b0;
            plaintext     <= 128'd0;
        end else begin
            done <= 1'b0;

            if (start && !running) begin
                round_key_reg <= key;
                round         <= 4'd0;
                phase         <= PHASE_KEYGEN;
                running       <= 1'b1;

            end else if (running && phase == PHASE_KEYGEN) begin
                if (round < 4'd9) begin
                    round_key_reg <= next_round_key;
                    round         <= round + 4'd1;
                end else begin
                    state <= ciphertext ^ next_round_key;
                    round <= 4'd9;
                    phase <= PHASE_DECRYPT;
                end

            end else if (running && phase == PHASE_DECRYPT) begin
                if (round > 4'd0) begin
                    state         <= after_invmix;
                    round_key_reg <= prev_round_key;
                    round         <= round - 4'd1;
                end else begin
                    plaintext <= after_addkey;
                    done      <= 1'b1;
                    running   <= 1'b0;
                    phase     <= PHASE_KEYGEN;
                    round     <= 4'd0;
                end
            end
        end
    end

endmodule
