`timescale 1ns / 1ps

module uart_fifo #
(
    parameter DATA_WIDTH = 8
)
(
    input  wire                   clk,
    input  wire                   rst,

    // Giao diện phía USER (Nối với APB Wrapper)
    input  wire [DATA_WIDTH-1:0]  tx_data_in,
    input  wire                   tx_valid_in,
    output wire                   tx_ready_out, 

    output wire [DATA_WIDTH-1:0]  rx_data_out,
    output wire                   rx_valid_out, 
    input  wire                   rx_ready_in,

    // Giao diện vật lý UART
    input  wire                   rxd,
    output wire                   txd,
    
    // Tín hiệu Status mới để báo về Wrapper
    output wire                   overrun_error,
    output wire                   tx_empty,
    
    // Cấu hình
    input  wire [15:0]            prescale
);

    // --- DÂY NỐI NỘI BỘ ---
    wire [DATA_WIDTH-1:0] fifo_tx_data;
    wire                  fifo_tx_valid;
    wire                  fifo_tx_ready;

    wire [DATA_WIDTH-1:0] uart_rx_data;
    wire                  uart_rx_valid;
    wire                  uart_rx_ready;

    // Tín hiệu status từ core
    wire tx_busy;
    wire tx_fifo_empty_internal;

    // --- 1. LOGIC TÍNH TOÁN TX_EMPTY ---
    // Hệ thống thực sự trống khi: FIFO TX hết hàng VÀ Core UART đã truyền xong bit cuối
    assign tx_empty = tx_fifo_empty_internal && !tx_busy;

    // ----------------------------------------------------------------
    // 2. INSTANCE: TX FIFO
    // ----------------------------------------------------------------
    axis_fifo_uart #( .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(4) ) 
    fifo_tx_inst (
        .clk(clk), .rst(rst),
        .s_axis_tdata(tx_data_in), .s_axis_tvalid(tx_valid_in), .s_axis_tready(tx_ready_out),
        .m_axis_tdata(fifo_tx_data), .m_axis_tvalid(fifo_tx_valid), .m_axis_tready(fifo_tx_ready),
        .empty(tx_fifo_empty_internal) // Lấy tín hiệu báo rỗng từ FIFO
    );

    // ----------------------------------------------------------------
    // 3. INSTANCE: CORE UART (Gom RX và TX)
    // ----------------------------------------------------------------
    uart #( .DATA_WIDTH(DATA_WIDTH) ) 
    uart_core_inst (
        .clk(clk), .rst(rst),
        .s_axis_tdata(fifo_tx_data), .s_axis_tvalid(fifo_tx_valid), .s_axis_tready(fifo_tx_ready),
        .m_axis_tdata(uart_rx_data), .m_axis_tvalid(uart_rx_valid), .m_axis_tready(uart_rx_ready),
        .rxd(rxd), .txd(txd),
        .tx_busy(tx_busy),          // Lấy tín hiệu bận để tính tx_empty
        .rx_busy(),                 // Không dùng
        .rx_overrun_error(overrun_error), // Đẩy lỗi tràn lên Wrapper
        .rx_frame_error(),          // Có thể mở rộng sau
        .prescale(prescale)
    );

    // ----------------------------------------------------------------
    // 4. INSTANCE: RX FIFO
    // ----------------------------------------------------------------
    axis_fifo_uart #( .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(4) ) 
    fifo_rx_inst (
        .clk(clk), .rst(rst),
        .s_axis_tdata(uart_rx_data), .s_axis_tvalid(uart_rx_valid), .s_axis_tready(uart_rx_ready),
        .m_axis_tdata(rx_data_out), .m_axis_tvalid(rx_valid_out), .m_axis_tready(rx_ready_in)
        // chân empty/full của RX có thể dùng để làm ngắt RX_FULL nếu muốn
    );

endmodule
