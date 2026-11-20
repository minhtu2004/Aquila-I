// =============================================================================
// crc_apb_wrapper.v — APB slave for CPU to read CRC status/result
//
// Register map (word-addressed via paddr[3:2]):
//   0x00  status [0]  : crc_result_valid (read-only)
//   0x04  result [31:0]: CRC result (read-only, snapshot when valid)
//   0x08  ctrl   [0]  : write 1 to clear result_valid (soft ack)
//
// Note: DMA ack (crc_result_ack) takes priority; CPU ctrl just for debug/polling
// =============================================================================
module crc_apb_wrapper (
    input  wire        clk,
    input  wire        rst_n,

    // APB slave
    input  wire [11:0] apb_paddr,
    input  wire        apb_psel,
    input  wire        apb_penable,
    input  wire        apb_pwrite,
    input  wire [31:0] apb_pwdata,
    output reg  [31:0] apb_prdata,
    output wire        apb_pready,
    output wire        apb_pslverr,

    // to/from crc32_top
    input  wire [31:0] crc_result,
    input  wire        crc_result_valid,
    output reg         cpu_crc_ack       // CPU-side ack (OR'd with DMA ack in top)
);
    assign apb_pready  = 1'b1;
    assign apb_pslverr = 1'b0;

    wire apb_wr = apb_psel & apb_penable & apb_pwrite;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cpu_crc_ack <= 1'b0;
        else begin
            cpu_crc_ack <= 1'b0;
            if (apb_wr && apb_paddr[3:2] == 2'd2 && apb_pwdata[0])
                cpu_crc_ack <= 1'b1;
        end
    end

    always @(*) begin
        case (apb_paddr[3:2])
            2'd0:    apb_prdata = {31'd0, crc_result_valid};
            2'd1:    apb_prdata = crc_result;
            default: apb_prdata = 32'd0;
        endcase
    end
endmodule
