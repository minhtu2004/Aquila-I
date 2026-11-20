`timescale 1ns / 1ps
module axis_fifo_spi # (
    parameter DEPTH = 16,
    parameter DATA_WIDTH = 8
) (
    input  wire                   clk, rst,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready
);
    reg [4:0] wr_ptr;
    reg [4:0] rd_ptr;
    reg [DATA_WIDTH-1:0] mem [15:0];

    assign s_axis_tready = (wr_ptr != (rd_ptr ^ 5'b10000));
    assign m_axis_tvalid = (wr_ptr != rd_ptr);
    assign m_axis_tdata  = mem[rd_ptr[3:0]];

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 5'd0; 
            rd_ptr <= 5'd0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                mem[wr_ptr[3:0]] <= s_axis_tdata;
                wr_ptr <= wr_ptr + 5'd1;
            end
            if (m_axis_tvalid && m_axis_tready) begin
                rd_ptr <= rd_ptr + 5'd1;
            end
        end
    end
endmodule
