`timescale 1ns / 1ps

module i2c_master_top # (
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 64
) (
    input  wire                   clk, rst,
    // TX Path
    input  wire [DATA_WIDTH-1:0]  s_axis_data_tdata,
    input  wire                   s_axis_data_tvalid,
    output wire                   s_axis_data_tready, // Đưa tín hiệu này ra Wrapper
    input  wire                   s_axis_data_tlast,
    // Command Interface
    input  wire [6:0]             s_axis_cmd_address,
    input  wire                   s_axis_cmd_start,
    input  wire                   s_axis_cmd_read,
    input  wire                   s_axis_cmd_write,
    input  wire                   s_axis_cmd_write_multiple,
    input  wire                   s_axis_cmd_stop,
    input  wire                   s_axis_cmd_valid,
    output wire                   s_axis_cmd_ready,
    // Read Data Interface
    output wire [7:0]             m_axis_data_tdata,
    output wire                   m_axis_data_tvalid,
    input  wire                   m_axis_data_tready,
    output wire                   m_axis_data_tlast,
    // Physical I2C
    input  wire scl_i, output wire scl_o, output wire scl_t,
    input  wire sda_i, output wire sda_o, output wire sda_t,
    // Status
    input  wire [15:0]            prescale,
    input  wire                   stop_on_idle,
    output wire                   busy,
    output wire                   missed_ack
);
    wire [DATA_WIDTH-1:0] fifo_to_i2c_tdata;
    wire fifo_to_i2c_tvalid, fifo_to_i2c_tready, fifo_to_i2c_tlast;

    // TX FIFO 
    axis_fifo_i2c #(.DEPTH(FIFO_DEPTH), .DATA_WIDTH(DATA_WIDTH), .KEEP_ENABLE(0), .LAST_ENABLE(1), .PIPELINE_OUTPUT(2)) 
    tx_fifo_inst (
        .clk(clk), .rst(rst),
        .s_axis_tdata(s_axis_data_tdata), .s_axis_tvalid(s_axis_data_tvalid), .s_axis_tready(s_axis_data_tready),
        .s_axis_tlast(s_axis_data_tlast), .s_axis_tkeep(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_axis_tdata(fifo_to_i2c_tdata), .m_axis_tvalid(fifo_to_i2c_tvalid), .m_axis_tready(fifo_to_i2c_tready), .m_axis_tlast(fifo_to_i2c_tlast)
    );

    // I2C Master Core 
    i2c_master i2c_master_inst (
        .clk(clk), .rst(rst),
        .s_axis_cmd_address(s_axis_cmd_address), .s_axis_cmd_start(s_axis_cmd_start),
        .s_axis_cmd_read(s_axis_cmd_read), .s_axis_cmd_write(s_axis_cmd_write),
        .s_axis_cmd_write_multiple(s_axis_cmd_write_multiple), .s_axis_cmd_stop(s_axis_cmd_stop),
        .s_axis_cmd_valid(s_axis_cmd_valid), .s_axis_cmd_ready(s_axis_cmd_ready),
        .s_axis_data_tdata(fifo_to_i2c_tdata), .s_axis_data_tvalid(fifo_to_i2c_tvalid),
        .s_axis_data_tready(fifo_to_i2c_tready), .s_axis_data_tlast(fifo_to_i2c_tlast),
        .m_axis_data_tdata(m_axis_data_tdata), .m_axis_data_tvalid(m_axis_data_tvalid),
        .m_axis_data_tready(m_axis_data_tready), .m_axis_data_tlast(m_axis_data_tlast),
        .scl_i(scl_i), .scl_o(scl_o), .scl_t(scl_t), .sda_i(sda_i), .sda_o(sda_o), .sda_t(sda_t),
        .busy(busy), .missed_ack(missed_ack), .prescale(prescale), .stop_on_idle(stop_on_idle)
    );
endmodule
