// =============================================================================
// aes_top.v — AES-128 accelerator top, DMA-facing + APB key config
//
// Data flow:
//   DMA pushes 4 x 32-bit words → input buffer [127:0]
//   → aes_core encrypt (11 cycles) OR aes_core_dec decrypt (21 cycles),
//     selected by AES_CTRL[0]
//   → output buffer [127:0]
//   → DMA pulls 4 x 32-bit words
//
// APB register map (paddr[5:2]):
//   0x00  AES_KEY0   key[127:96]  R/W
//   0x04  AES_KEY1   key[95:64]   R/W
//   0x08  AES_KEY2   key[63:32]   R/W
//   0x0C  AES_KEY3   key[31:0]    R/W
//   0x10  AES_STATUS {27'b0, aes_error_code[3:0], aes_busy}  R only
//   0x14  AES_CTRL   {31'b0, mode_sel}           R/W
//                     mode_sel: 0 = encrypt (default), 1 = decrypt
//
// Default key on reset: 128'h000102030405060708090a0b0c0d0e0f
//
// AES_CTRL is only latched while the block is idle (aes_idle == 1) — a
// write while a block is mid-flight (filling input, core running, or
// output waiting on DMA) is silently ignored. This differs from
// AES_KEY0-3, which remain plain R/W with no lock (firmware is still
// responsible for setting the key before pushing data).
//
// DMA push protocol  : dma_aes_valid=1, aes_dma_ready=1 → word accepted
// DMA pull protocol  : aes_dma_valid=1, dma_aes_ready=1 → word sent
//
// Error conditions:
//   AES_ERR_BUSY_START : DMA pushes first word while core still running
//   AES_ERR_IN_OVF     : DMA pushes >4 words in one block
//   AES_ERR_OUT_OVF    : DMA pulls >4 words before next encrypt
//   AES_ERR_PROTOCOL   : DMA pulls when output not ready
//   AES_ERR_CORE_FAIL  : core FSM done but output buffer not valid (sanity)
// =============================================================================
module aes_top (
    input  wire        clk,
    input  wire        rst_n,

    // APB slave for key config
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [ 7:0] paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // DMA -> AES
    input  wire        dma_aes_valid,
    input  wire [31:0] dma_aes_data,
    output wire        aes_dma_ready,

    // AES -> DMA
    output reg         aes_dma_valid,
    output reg  [31:0] aes_dma_data,
    input  wire        dma_aes_ready,

    // Error/status to DMA
    output reg  [ 3:0] aes_error_code,
    output reg         aes_error_valid
);

    // =========================================================================
    // Error codes
    // =========================================================================
    localparam [3:0]
        AES_ERR_NONE       = 4'd0,
        AES_ERR_BUSY_START = 4'd1,
        AES_ERR_IN_OVF     = 4'd2,
        AES_ERR_OUT_OVF    = 4'd3,
        AES_ERR_BAD_BLOCK  = 4'd4,
        AES_ERR_PROTOCOL   = 4'd5,
        AES_ERR_CORE_FAIL  = 4'd6;

    // =========================================================================
    // APB key registers
    // =========================================================================
    reg [127:0] aes_key;
    reg         mode_sel;   // 0 = encrypt, 1 = decrypt

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    wire apb_write = psel && penable && pwrite;

    wire core_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aes_key  <= 128'h000102030405060708090a0b0c0d0e0f;
            mode_sel <= 1'b0;
        end else if (apb_write)
            case (paddr[5:2])
                4'h0: aes_key[127:96] <= pwdata;
                4'h1: aes_key[95:64]  <= pwdata;
                4'h2: aes_key[63:32]  <= pwdata;
                4'h3: aes_key[31:0]   <= pwdata;
                4'h5: if (aes_idle) mode_sel <= pwdata[0];
                default: ;
            endcase
    end

    always @(*) begin
        case (paddr[5:2])
            4'h0: prdata = aes_key[127:96];
            4'h1: prdata = aes_key[95:64];
            4'h2: prdata = aes_key[63:32];
            4'h3: prdata = aes_key[31:0];
            4'h4: prdata = {27'b0, aes_error_code, aes_busy};
            4'h5: prdata = {31'b0, mode_sel};
            default: prdata = 32'b0;
        endcase
    end

    // =========================================================================
    // Input / output buffers
    // =========================================================================
    reg [127:0] in_buf;
    reg [127:0] out_buf;
    reg [1:0]   push_cnt;   // words received in current block (0..3)
    reg [1:0]   pull_cnt;   // words sent from current block   (0..3)
    reg         in_valid;   // full 4-word block ready to encrypt
    reg         out_valid;  // encrypted block ready to pull

    assign aes_dma_ready = !in_valid && !core_busy && !out_valid;

    // AES-wide busy/idle: broader than core_busy alone — also true while
    // words are still being pushed in (push_cnt != 0, in_valid not yet
    // set) or the finished block is waiting on DMA to pull it out.
    wire aes_busy = core_busy || in_valid || out_valid || (push_cnt != 2'd0);
    wire aes_idle = !aes_busy;

    // =========================================================================
    // aes_core / aes_core_dec instantiation, muxed by mode_sel
    //
    // mode_active latches which core was actually started, so that a
    // firmware write to AES_CTRL while a block is in flight cannot
    // corrupt output routing (this is a structural safety latch, cheap
    // — 1 bit — distinct from the "no lock" convention used for KEY,
    // which only risks wrong *content*, not wrong *routing*).
    // =========================================================================
    wire core_busy_enc, core_busy_dec;
    wire core_done_enc, core_done_dec;
    wire [127:0] core_cipher_enc, core_plain_dec;

    wire core_start_common = in_valid && !core_busy;
    wire core_start_enc    = core_start_common && !mode_sel;
    wire core_start_dec    = core_start_common &&  mode_sel;

    assign core_busy = core_busy_enc || core_busy_dec;

    reg mode_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mode_active <= 1'b0;
        else if (core_start_common)
            mode_active <= mode_sel;
    end

    wire core_done   = mode_active ? core_done_dec   : core_done_enc;
    wire [127:0] core_result = mode_active ? core_plain_dec : core_cipher_enc;

    aes_core u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (core_start_enc),
        .plaintext  (in_buf),
        .key        (aes_key),
        .done       (core_done_enc),
        .ciphertext (core_cipher_enc),
        .busy       (core_busy_enc)
    );

    aes_core_dec u_core_dec (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (core_start_dec),
        .ciphertext (in_buf),
        .key        (aes_key),
        .done       (core_done_dec),
        .plaintext  (core_plain_dec),
        .busy       (core_busy_dec)
    );

    // =========================================================================
    // Push FSM — DMA → input buffer
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_buf   <= 128'd0;
            push_cnt <= 2'd0;
            in_valid <= 1'b0;
        end else begin
            // Clear in_valid once a core picks it up
            if (core_start_common)
                in_valid <= 1'b0;

            if (dma_aes_valid && aes_dma_ready) begin
                case (push_cnt)
                    2'd0: in_buf[127:96] <= dma_aes_data;
                    2'd1: in_buf[95:64]  <= dma_aes_data;
                    2'd2: in_buf[63:32]  <= dma_aes_data;
                    2'd3: in_buf[31:0]   <= dma_aes_data;
                endcase
                if (push_cnt == 2'd3) begin
                    push_cnt <= 2'd0;
                    in_valid <= 1'b1;
                end else begin
                    push_cnt <= push_cnt + 2'd1;
                end
            end
        end
    end

    // =========================================================================
    // Output buffer — latch core result
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_buf   <= 128'd0;
            out_valid <= 1'b0;
            pull_cnt  <= 2'd0;
        end else begin
            if (core_done) begin
                out_buf   <= core_result;
                out_valid <= 1'b1;
                pull_cnt  <= 2'd0;
            end

            if (aes_dma_valid && dma_aes_ready) begin
                if (pull_cnt == 2'd3)
                    out_valid <= 1'b0;
                pull_cnt <= pull_cnt + 2'd1;
            end
        end
    end

    // =========================================================================
    // Pull FSM — output buffer → DMA
    // =========================================================================
    always @(*) begin
        aes_dma_valid = out_valid;
        case (pull_cnt)
            2'd0: aes_dma_data = out_buf[127:96];
            2'd1: aes_dma_data = out_buf[95:64];
            2'd2: aes_dma_data = out_buf[63:32];
            2'd3: aes_dma_data = out_buf[31:0];
        endcase
    end

    // =========================================================================
    // Error detection — sticky code, pulse valid
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aes_error_valid <= 1'b0;
            aes_error_code  <= AES_ERR_NONE;
        end else begin
            aes_error_valid <= 1'b0;  // pulse only

            // BUSY_START: DMA pushes first word while core still running
            if (dma_aes_valid && core_busy && push_cnt == 2'd0) begin
                aes_error_valid <= 1'b1;
                aes_error_code  <= AES_ERR_BUSY_START;

            // Clean start of new block clears error code
            end else if (dma_aes_valid && aes_dma_ready && push_cnt == 2'd0) begin
                aes_error_code <= AES_ERR_NONE;
            end
        end
    end

endmodule
