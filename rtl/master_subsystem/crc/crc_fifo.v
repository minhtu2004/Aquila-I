// =============================================================================
// crc_fifo.v — 33-bit FIFO (32-bit data + last flag), depth 8
// Wraps axis_fifo_uart with DATA_WIDTH=33, ADDR_WIDTH=3
// =============================================================================
module crc_fifo (
    input  wire        clk,
    input  wire        rst,

    // write side (from DMA)
    input  wire [31:0] s_data,
    input  wire        s_last,
    input  wire        s_valid,
    output wire        s_ready,

    // read side (to crc32_core)
    output wire [31:0] m_data,
    output wire        m_last,
    output wire        m_valid,
    input  wire        m_ready,

    output wire        empty,
    output wire        full
);
    wire [32:0] s_tdata = {s_last, s_data};
    wire [32:0] m_tdata;

    assign m_data = m_tdata[31:0];
    assign m_last = m_tdata[32];

    axis_fifo_uart #(
        .DATA_WIDTH(33),
        .ADDR_WIDTH(3)   // depth 8
    ) u_fifo (
        .clk          (clk),
        .rst          (rst),
        .s_axis_tdata (s_tdata),
        .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready),
        .m_axis_tdata (m_tdata),
        .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready),
        .empty        (empty),
        .full         (full)
    );
endmodule
