// =============================================================================
// dma.v — Single-channel DMA (rev5)
//
// Modes:
//   00  MEM_TO_MEM  : src RAM → dst RAM, word-by-word
//   01  MEM_TO_CRC  : src RAM → CRC engine, crc_last on final word
//   10  CRC_TO_MEM  : wait crc_result_valid → write 1 word to dst
//   11  AES_ENC     : src RAM → AES encrypt → dst RAM, 4-word blocks
//
// Rules:
//   R1. cur_src / cur_dst advance ONLY in UPDATE_COUNT
//   R2. aes_push_cnt / aes_pull_cnt separate 2-bit counters
//   R3. crc_result_ack pulses ONLY after AXI write OKAY
//   R4. AES_ENC requires len[1:0] == 2'b00
//   R5. cur_len decremented only during AES push phase (or non-AES modes)
//   R6. AR channel uses ar_done flag, symmetric with aw_done/w_done
//   R7. status is sticky; cleared only when ctrl[1]=1 or new job starts
//   R8. Accelerator errors (crc_error_valid / aes_error_valid) are gated by
//       mode and busy; on detection DMA latches reg_error and jumps S_ERROR
//       immediately (fail-fast). Only one error source active per job.
//
// Register map:
//   0x00  src      [31:0]
//   0x04  dst      [31:0]
//   0x08  len      [15:0]
//   0x0C  mode     [1:0]
//   0x10  ctrl     [1:0]  write-only: [0]=start [1]=clear status+error
//   0x14  status   [2:0]  {error, done, busy}  — sticky (R7)
//   0x18  error    [5:0]  {source[1:0], code[3:0]} — sticky, cleared with status
//
// ctrl[0] = start
// ctrl[1] = clear status (done/error) and reg_error
// =============================================================================

module dma #(
    parameter APB_ADDR_WIDTH = 12
)(
    input  wire        clk,
    input  wire        rst_n,

    // APB slave
    input  wire [APB_ADDR_WIDTH-1:0] apb_paddr,
    input  wire        apb_psel,
    input  wire        apb_penable,
    input  wire        apb_pwrite,
    input  wire [31:0] apb_pwdata,
    output reg  [31:0] apb_prdata,
    output wire        apb_pready,
    output wire        apb_pslverr,

    // AXI4-Lite master — write
    output reg  [31:0] axi_awaddr,
    output reg         axi_awvalid,
    input  wire        axi_awready,
    output reg  [31:0] axi_wdata,
    output reg  [ 3:0] axi_wstrb,
    output reg         axi_wvalid,
    input  wire        axi_wready,
    input  wire [ 1:0] axi_bresp,
    input  wire        axi_bvalid,
    output reg         axi_bready,

    // AXI4-Lite master — read
    output reg  [31:0] axi_araddr,
    output reg         axi_arvalid,
    input  wire        axi_arready,
    input  wire [31:0] axi_rdata,
    input  wire [ 1:0] axi_rresp,
    input  wire        axi_rvalid,
    output reg         axi_rready,

    // Internal — AES
    output reg         dma_aes_valid,
    output reg  [31:0] dma_aes_data,
    input  wire        aes_dma_ready,
    input  wire        aes_dma_valid,
    input  wire [31:0] aes_dma_data,
    output reg         dma_aes_ready,

    // Internal — CRC
    output reg         dma_crc_start,
    output reg         dma_crc_valid,
    output reg  [31:0] dma_crc_data,
    output reg         dma_crc_last,
    input  wire        crc_dma_ready,
    input  wire [31:0] crc_result,
    input  wire        crc_result_valid,
    output reg         crc_result_ack,
    input  wire [ 3:0] crc_error_code,   // R8: error code from CRC core
    input  wire        crc_error_valid,  // R8: pulses when CRC detects error

    // Internal — AES error reporting
    input  wire [ 3:0] aes_error_code,   // R8: error code from AES core
    input  wire        aes_error_valid,  // R8: pulses when AES detects error

    // IRQ
    output reg         dma_done_irq
);

    assign apb_pready  = 1'b1;
    assign apb_pslverr = 1'b0;

    // =========================================================================
    // Register map
    //   0x00  src      [31:0]
    //   0x04  dst      [31:0]
    //   0x08  len      [15:0]
    //   0x0C  mode     [1:0]
    //   0x10  ctrl     [1:0]  write-only: [0]=start [1]=clear status+error
    //   0x14  status   [2:0]  {error, done, busy}  — sticky (R7)
    //   0x18  error    [5:0]  {source[1:0], code[3:0]} — sticky (R8)
    // =========================================================================
    localparam [1:0] MODE_MEM_MEM = 2'd0,
                     MODE_MEM_CRC = 2'd1,
                     MODE_CRC_MEM = 2'd2,
                     MODE_AES_ENC = 2'd3;

    // =========================================================================
    // Error source encoding  (reg_error[5:4])
    // =========================================================================
    localparam [1:0]
        ERR_SRC_NONE = 2'b00,
        ERR_SRC_CRC  = 2'b01,
        ERR_SRC_AES  = 2'b10,
        ERR_SRC_DMA  = 2'b11;

    // CRC error codes  (reg_error[3:0] when source = ERR_SRC_CRC)
    localparam [3:0]
        CRC_ERR_NONE       = 4'd0,
        CRC_ERR_BUSY_START = 4'd1,
        CRC_ERR_FIFO_OVF   = 4'd2,
        CRC_ERR_BAD_LAST   = 4'd3,
        CRC_ERR_PROTOCOL   = 4'd4;

    // AES error codes  (reg_error[3:0] when source = ERR_SRC_AES)
    localparam [3:0]
        AES_ERR_NONE       = 4'd0,
        AES_ERR_BUSY_START = 4'd1,
        AES_ERR_IN_OVF     = 4'd2,
        AES_ERR_OUT_OVF    = 4'd3,
        AES_ERR_BAD_BLOCK  = 4'd4,
        AES_ERR_PROTOCOL   = 4'd5,
        AES_ERR_CORE_FAIL  = 4'd6;

    // DMA-local error codes  (reg_error[3:0] when source = ERR_SRC_DMA)
    localparam [3:0]
        DMA_LOCAL_ERR_NONE      = 4'd0,
        DMA_LOCAL_ERR_ZERO_LEN  = 4'd1,
        DMA_LOCAL_ERR_AES_ALIGN = 4'd2,
        DMA_LOCAL_ERR_AXI_READ  = 4'd3,
        DMA_LOCAL_ERR_AXI_WRITE = 4'd4,
        DMA_LOCAL_ERR_BAD_MODE  = 4'd5,
        DMA_LOCAL_ERR_BUSY      = 4'd6;

    reg [31:0] reg_src;
    reg [31:0] reg_dst;
    reg [15:0] reg_len;
    reg [ 1:0] reg_mode;
    reg [ 2:0] reg_status;   // {error, done, busy}
    reg [ 5:0] reg_error;    // {source[1:0], code[3:0]} — R8

    reg start_req;
    reg clear_req;

    wire apb_wr = apb_psel & apb_penable & apb_pwrite;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_src  <= 0; reg_dst <= 0;
            reg_len  <= 0; reg_mode <= 0;
            start_req <= 0; clear_req <= 0;
        end else begin
            start_req <= 1'b0;
            clear_req <= 1'b0;
            if (apb_wr) begin
                case (apb_paddr[5:2])
                    4'd0: reg_src  <= apb_pwdata;
                    4'd1: reg_dst  <= apb_pwdata;
                    4'd2: reg_len  <= apb_pwdata[15:0];
                    4'd3: reg_mode <= apb_pwdata[1:0];
                    4'd4: begin
                        if (apb_pwdata[0]) start_req <= 1'b1;
                        if (apb_pwdata[1]) clear_req <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (apb_paddr[5:2])
            4'd0:    apb_prdata = reg_src;
            4'd1:    apb_prdata = reg_dst;
            4'd2:    apb_prdata = {16'd0, reg_len};
            4'd3:    apb_prdata = {30'd0, reg_mode};
            4'd4:    apb_prdata = 32'd0;
            4'd5:    apb_prdata = {29'd0, reg_status};
            4'd6:    apb_prdata = {26'd0, reg_error};
            default: apb_prdata = 32'd0;
        endcase
    end

    // =========================================================================
    // FSM states
    // =========================================================================
    localparam [3:0]
        S_IDLE             = 4'd0,
        S_READ_RAM         = 4'd1,
        S_DISPATCH         = 4'd2,
        S_WRITE_RAM        = 4'd3,
        S_PUSH_CRC         = 4'd4,
        S_PUSH_AES         = 4'd5,
        S_PULL_AES         = 4'd6,
        S_WRITE_CRC_RESULT = 4'd7,
        S_UPDATE_COUNT     = 4'd8,
        S_DONE             = 4'd9,
        S_ERROR            = 4'd10;

    reg [3:0] state;

    // =========================================================================
    // Working registers
    // =========================================================================
    reg [31:0] cur_src;
    reg [31:0] cur_dst;
    reg [15:0] cur_len;
    reg [31:0] word_buf;

    reg [1:0]  aes_push_cnt;
    reg [1:0]  aes_pull_cnt;
    reg        aes_phase;
    localparam AES_PUSH_PHASE = 1'b0;
    localparam AES_PULL_PHASE = 1'b1;

    // AXI handshake flags (R6: ar_done symmetric with aw_done/w_done)
    reg ar_done;
    reg aw_done;
    reg w_done;

    // =========================================================================
    // Start error checks
    // =========================================================================
    wire err_busy  = start_req & reg_status[0];
    wire err_zero  = start_req & (reg_mode != MODE_CRC_MEM) & (reg_len == 16'd0);
    wire err_align = start_req & (reg_mode == MODE_AES_ENC) & (reg_len[1:0] != 2'b00);
    wire any_err   = err_busy | err_zero | err_align;

    // =========================================================================
    // FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            reg_status     <= 3'd0;
            reg_error      <= 6'd0;
            dma_done_irq   <= 1'b0;
            crc_result_ack <= 1'b0;
            cur_src  <= 0; cur_dst <= 0; cur_len <= 0; word_buf <= 0;
            aes_push_cnt <= 0; aes_pull_cnt <= 0;
            aes_phase    <= AES_PUSH_PHASE;
            ar_done <= 0; aw_done <= 0; w_done <= 0;
            axi_awaddr <= 0; axi_awvalid <= 0;
            axi_wdata  <= 0; axi_wstrb   <= 4'hF; axi_wvalid <= 0;
            axi_bready <= 0;
            axi_araddr <= 0; axi_arvalid <= 0; axi_rready <= 0;
            dma_aes_valid <= 0; dma_aes_data <= 0; dma_aes_ready <= 0;
            dma_crc_start <= 0;
            dma_crc_valid <= 0; dma_crc_data <= 0; dma_crc_last  <= 0;
        end else begin
            dma_done_irq   <= 1'b0;
            crc_result_ack <= 1'b0;
            dma_crc_start  <= 1'b0;   // pulse 1 cycle only

            // R7: clear_req clears done/error bits any time (not busy)
            if (clear_req && !start_req) begin
                reg_status <= reg_status & 3'b001;  // preserve busy, clear done+error
                reg_error  <= 6'd0;
            end

            // -----------------------------------------------------------------
            // R8: Accelerator error — fail-fast, gated by mode + busy
            // -----------------------------------------------------------------
            // crc_err_active: CRC/CRC_TO_MEM modes only
            // aes_err_active: AES_ENC mode only
            // Checked before case(state) so any active state jumps to S_ERROR
            // -----------------------------------------------------------------
            if (reg_status[0] &&
                ((reg_mode == MODE_MEM_CRC) || (reg_mode == MODE_CRC_MEM)) &&
                crc_error_valid) begin
                reg_status <= 3'b100;
                reg_error  <= {ERR_SRC_CRC, crc_error_code};
                state      <= S_ERROR;
            end else if (reg_status[0] &&
                         (reg_mode == MODE_AES_ENC) &&
                         aes_error_valid) begin
                reg_status <= 3'b100;
                reg_error  <= {ERR_SRC_AES, aes_error_code};
                state      <= S_ERROR;
            end else begin

            case (state)

                // -------------------------------------------------------------
                S_IDLE: begin
                    // R7: IDLE does NOT auto-clear status
                    if (start_req) begin
                        if (any_err) begin
                            reg_status <= 3'b100;   // error, sticky
                            // set specific DMA-local error code
                            if (err_busy)
                                reg_error <= {ERR_SRC_DMA, DMA_LOCAL_ERR_BUSY};
                            else if (err_align)
                                reg_error <= {ERR_SRC_DMA, DMA_LOCAL_ERR_AES_ALIGN};
                            else  // err_zero
                                reg_error <= {ERR_SRC_DMA, DMA_LOCAL_ERR_ZERO_LEN};
                            state      <= S_ERROR;
                        end else begin
                            reg_status   <= 3'b001;  // busy (clears done/error)
                            reg_error    <= 6'd0;    // clear error on new job
                            cur_src      <= reg_src;
                            cur_dst      <= reg_dst;
                            cur_len      <= reg_len;
                            aes_push_cnt <= 2'd0;
                            aes_pull_cnt <= 2'd0;
                            aes_phase    <= AES_PUSH_PHASE;
                            ar_done      <= 1'b0;
                            aw_done      <= 1'b0;
                            w_done       <= 1'b0;
                            if (reg_mode == MODE_MEM_CRC)
                                dma_crc_start <= 1'b1;
                            state <= (reg_mode == MODE_CRC_MEM) ? S_WRITE_CRC_RESULT
                                                                 : S_READ_RAM;
                        end
                    end
                end

                // -------------------------------------------------------------
                // AXI read — ar_done tracks address phase (R6)
                // -------------------------------------------------------------
                S_READ_RAM: begin
                    // Address phase
                    if (!ar_done & !axi_arvalid) begin
                        axi_araddr  <= cur_src;
                        axi_arvalid <= 1'b1;
                    end
                    if (axi_arvalid & axi_arready) begin
                        axi_arvalid <= 1'b0;
                        ar_done     <= 1'b1;
                    end

                    // Data phase — only after address accepted
                    if (ar_done | (axi_arvalid & axi_arready))
                        axi_rready <= 1'b1;

                    if (axi_rvalid & axi_rready) begin
                        axi_rready <= 1'b0;
                        ar_done    <= 1'b0;
                        if (axi_rresp != 2'b00) begin
                            reg_status <= 3'b100;
                            reg_error  <= {ERR_SRC_DMA, DMA_LOCAL_ERR_AXI_READ};
                            state      <= S_ERROR;
                        end else begin
                            word_buf <= axi_rdata;
                            state    <= S_DISPATCH;
                        end
                    end
                end

                // -------------------------------------------------------------
                S_DISPATCH: begin
                    case (reg_mode)
                        MODE_MEM_MEM: state <= S_WRITE_RAM;
                        MODE_MEM_CRC: state <= S_PUSH_CRC;
                        MODE_AES_ENC: state <= S_PUSH_AES;
                        default: begin
                            reg_status <= 3'b100;
                            reg_error  <= {ERR_SRC_DMA, DMA_LOCAL_ERR_BAD_MODE};
                            state      <= S_ERROR;
                        end
                    endcase
                end

                // -------------------------------------------------------------
                S_WRITE_RAM: begin
                    if (!aw_done & !axi_awvalid) begin
                        axi_awaddr  <= cur_dst;
                        axi_awvalid <= 1'b1;
                    end
                    if (axi_awvalid & axi_awready) begin
                        axi_awvalid <= 1'b0;
                        aw_done     <= 1'b1;
                    end

                    if (!w_done & !axi_wvalid) begin
                        axi_wdata  <= word_buf;
                        axi_wstrb  <= 4'hF;
                        axi_wvalid <= 1'b1;
                    end
                    if (axi_wvalid & axi_wready) begin
                        axi_wvalid <= 1'b0;
                        w_done     <= 1'b1;
                    end

                    if ((aw_done | (axi_awvalid & axi_awready)) &
                        (w_done  | (axi_wvalid  & axi_wready)))
                        axi_bready <= 1'b1;

                    if (axi_bvalid & axi_bready) begin
                        axi_bready <= 1'b0;
                        aw_done    <= 1'b0;
                        w_done     <= 1'b0;
                        if (axi_bresp != 2'b00) begin
                            reg_status <= 3'b100;
                            reg_error  <= {ERR_SRC_DMA, DMA_LOCAL_ERR_AXI_WRITE};
                            state      <= S_ERROR;
                        end else
                            state <= S_UPDATE_COUNT;
                    end
                end

                // -------------------------------------------------------------
                S_PUSH_CRC: begin
                    dma_crc_valid <= 1'b1;
                    dma_crc_data  <= word_buf;
                    dma_crc_last  <= (cur_len == 16'd1);
                    if (crc_dma_ready & dma_crc_valid) begin
                        dma_crc_valid <= 1'b0;
                        dma_crc_last  <= 1'b0;
                        state         <= S_UPDATE_COUNT;
                    end
                end

                // -------------------------------------------------------------
                S_PUSH_AES: begin
                    dma_aes_valid <= 1'b1;
                    dma_aes_data  <= word_buf;
                    if (aes_dma_ready & dma_aes_valid) begin
                        dma_aes_valid <= 1'b0;
                        state         <= S_UPDATE_COUNT;
                    end
                end

                // -------------------------------------------------------------
                S_PULL_AES: begin
                    dma_aes_ready <= 1'b1;
                    if (aes_dma_valid & dma_aes_ready) begin
                        dma_aes_ready <= 1'b0;
                        word_buf      <= aes_dma_data;
                        state         <= S_WRITE_RAM;
                    end
                end

                // -------------------------------------------------------------
                S_WRITE_CRC_RESULT: begin
                    if (crc_result_valid) begin
                        if (!aw_done & !axi_awvalid) begin
                            axi_awaddr  <= cur_dst;
                            axi_awvalid <= 1'b1;
                        end
                        if (axi_awvalid & axi_awready) begin
                            axi_awvalid <= 1'b0;
                            aw_done     <= 1'b1;
                        end

                        if (!w_done & !axi_wvalid) begin
                            axi_wdata  <= crc_result;
                            axi_wstrb  <= 4'hF;
                            axi_wvalid <= 1'b1;
                        end
                        if (axi_wvalid & axi_wready) begin
                            axi_wvalid <= 1'b0;
                            w_done     <= 1'b1;
                        end

                        if ((aw_done | (axi_awvalid & axi_awready)) &
                            (w_done  | (axi_wvalid  & axi_wready)))
                            axi_bready <= 1'b1;

                        if (axi_bvalid & axi_bready) begin
                            axi_bready <= 1'b0;
                            aw_done    <= 1'b0;
                            w_done     <= 1'b0;
                            if (axi_bresp != 2'b00) begin
                                reg_status <= 3'b100;
                                reg_error  <= {ERR_SRC_DMA, DMA_LOCAL_ERR_AXI_WRITE};
                                state      <= S_ERROR;
                            end else begin
                                crc_result_ack <= 1'b1;  // R3
                                state          <= S_DONE;
                            end
                        end
                    end
                end

                // -------------------------------------------------------------
                // R1: ALL pointer/counter advances here
                // R5: cur_len decremented only in AES push phase (or non-AES)
                // -------------------------------------------------------------
                S_UPDATE_COUNT: begin
                    case (reg_mode)

                        MODE_MEM_MEM: begin
                            cur_src <= cur_src + 4;
                            cur_dst <= cur_dst + 4;
                            cur_len <= cur_len - 1'b1;
                            state   <= (cur_len == 16'd1) ? S_DONE : S_READ_RAM;
                        end

                        MODE_MEM_CRC: begin
                            cur_src <= cur_src + 4;
                            cur_len <= cur_len - 1'b1;
                            state   <= (cur_len == 16'd1) ? S_DONE : S_READ_RAM;
                        end

                        MODE_AES_ENC: begin
                            if (aes_phase == AES_PUSH_PHASE) begin
                                cur_src      <= cur_src + 4;
                                cur_len      <= cur_len - 1'b1;       // R5
                                aes_push_cnt <= aes_push_cnt + 1'b1;
                                if (aes_push_cnt == 2'd3) begin
                                    aes_push_cnt <= 2'd0;
                                    aes_phase    <= AES_PULL_PHASE;
                                    state        <= S_PULL_AES;
                                end else begin
                                    state <= S_READ_RAM;
                                end
                            end else begin
                                // pull phase: advance dst, NO cur_len-- (R5)
                                cur_dst      <= cur_dst + 4;
                                aes_pull_cnt <= aes_pull_cnt + 1'b1;
                                if (aes_pull_cnt == 2'd3) begin
                                    aes_pull_cnt <= 2'd0;
                                    if (cur_len == 16'd0) begin
                                        state <= S_DONE;
                                    end else begin
                                        aes_phase <= AES_PUSH_PHASE;
                                        state     <= S_READ_RAM;
                                    end
                                end else begin
                                    state <= S_PULL_AES;
                                end
                            end
                        end

                        default: state <= S_DONE;
                    endcase
                end

                // -------------------------------------------------------------
                S_DONE: begin
                    reg_status   <= 3'b010;  // done sticky (R7)
                    dma_done_irq <= 1'b1;
                    state        <= S_IDLE;
                end

                S_ERROR: begin
                    reg_status   <= 3'b100;   // guaranteed error, even if caller forgot
                    dma_done_irq <= 1'b1;

                    // Clear all AXI handshake signals — fail clean
                    axi_awvalid <= 1'b0;
                    axi_wvalid  <= 1'b0;
                    axi_bready  <= 1'b0;
                    axi_arvalid <= 1'b0;
                    axi_rready  <= 1'b0;

                    // Clear accelerator handshake signals
                    dma_crc_valid <= 1'b0;
                    dma_crc_last  <= 1'b0;
                    dma_aes_valid <= 1'b0;
                    dma_aes_ready <= 1'b0;

                    // Clear AXI transaction flags
                    ar_done <= 1'b0;
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;

                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
            end  // else: no accelerator error

        end
    end

endmodule
