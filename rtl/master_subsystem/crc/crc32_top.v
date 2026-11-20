// =============================================================================
// crc32_top.v — CRC FIFO + core, DMA-facing interface
//
// DMA side:
//   dma_crc_start   : pulse to reset CRC for new job
//   dma_crc_valid   : DMA pushes word into FIFO
//   dma_crc_data    : 32-bit word
//   dma_crc_last    : last word of stream
//   crc_dma_ready   : FIFO not full (backpressure to DMA)
//   crc_result      : 32-bit CRC result
//   crc_result_valid: result ready
//   crc_result_ack  : DMA acks result (clears valid)
//
// Error reporting:
//   crc_error_valid : pulses 1 cycle when error detected
//   crc_error_code  : error code (see CRC_ERR_* localparams)
//
// Error conditions detected:
//   CRC_ERR_BUSY_START : dma_crc_start while result already valid (job overlap)
//   CRC_ERR_FIFO_OVF   : dma_crc_valid while FIFO full (overflow attempt)
//   CRC_ERR_BAD_LAST   : dma_crc_last asserted without dma_crc_valid
//   CRC_ERR_PROTOCOL   : dma_crc_valid while crc_result_valid not yet acked
// =============================================================================
module crc32_top (
    input  wire        clk,
    input  wire        rst_n,
    // DMA interface
    input  wire        dma_crc_start,
    input  wire        dma_crc_valid,
    input  wire [31:0] dma_crc_data,
    input  wire        dma_crc_last,
    output wire        crc_dma_ready,
    output reg  [31:0] crc_result,
    output reg         crc_result_valid,
    input  wire        crc_result_ack,
    // Error reporting
    output reg  [ 3:0] crc_error_code,
    output reg         crc_error_valid
);

    // =========================================================================
    // Error codes
    // =========================================================================
    localparam [3:0]
        CRC_ERR_NONE       = 4'd0,
        CRC_ERR_BUSY_START = 4'd1,
        CRC_ERR_FIFO_OVF   = 4'd2,
        CRC_ERR_BAD_LAST   = 4'd3,
        CRC_ERR_PROTOCOL   = 4'd4;

    wire        fifo_empty, fifo_full;
    wire        fifo_s_ready;
    wire [31:0] fifo_m_data;
    wire        fifo_m_last;
    wire        fifo_m_valid;
    wire        fifo_m_ready;
    wire        core_result_valid;
    wire [31:0] core_result;

    assign crc_dma_ready = fifo_s_ready;

    // active-low rst_n → active-high rst for FIFO
    wire rst_p = ~rst_n;

    crc_fifo u_fifo (
        .clk    (clk),
        .rst    (rst_p),
        .s_data (dma_crc_data),
        .s_last (dma_crc_last),
        .s_valid(dma_crc_valid),
        .s_ready(fifo_s_ready),
        .m_data (fifo_m_data),
        .m_last (fifo_m_last),
        .m_valid(fifo_m_valid),
        .m_ready(fifo_m_ready),
        .empty  (fifo_empty),
        .full   (fifo_full)
    );

    crc32_core u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .crc_start   (dma_crc_start),
        .in_ready    (fifo_m_ready),
        .in_valid    (fifo_m_valid),
        .in_data     (fifo_m_data),
        .in_last     (fifo_m_last),
        .result_valid(core_result_valid),
        .result      (core_result)
    );

    // =========================================================================
    // Result latch — unchanged logic
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_result       <= 32'd0;
            crc_result_valid <= 1'b0;
        end else begin
            if (dma_crc_start) begin
                crc_result_valid <= 1'b0;
            end else if (core_result_valid) begin
                crc_result       <= core_result;
                crc_result_valid <= 1'b1;
            end else if (crc_result_ack) begin
                crc_result_valid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Error detection — priority: BUSY_START > FIFO_OVF > BAD_LAST > PROTOCOL
    // crc_error_valid pulses exactly 1 cycle per error event
    // crc_error_code is sticky until reset or new clean start
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_error_valid <= 1'b0;
            crc_error_code  <= CRC_ERR_NONE;
        end else begin
            crc_error_valid <= 1'b0;   // pulse only

            // CRC_ERR_BUSY_START: start arrived while previous result not yet acked
            if (dma_crc_start && crc_result_valid) begin
                crc_error_valid <= 1'b1;
                crc_error_code  <= CRC_ERR_BUSY_START;

            // CRC_ERR_FIFO_OVF: DMA pushes data into a full FIFO
            end else if (dma_crc_valid && fifo_full) begin
                crc_error_valid <= 1'b1;
                crc_error_code  <= CRC_ERR_FIFO_OVF;

            // CRC_ERR_BAD_LAST: last strobe without a valid data beat
            end else if (dma_crc_last && !dma_crc_valid) begin
                crc_error_valid <= 1'b1;
                crc_error_code  <= CRC_ERR_BAD_LAST;

            // CRC_ERR_PROTOCOL: new data pushed before previous result acked
            end else if (dma_crc_valid && crc_result_valid) begin
                crc_error_valid <= 1'b1;
                crc_error_code  <= CRC_ERR_PROTOCOL;

            // clean new job clears old error code
            end else if (dma_crc_start) begin
                crc_error_code <= CRC_ERR_NONE;
            end
        end
    end

endmodule
