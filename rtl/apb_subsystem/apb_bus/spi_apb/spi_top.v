module spi_top # ( parameter FIFO_DEPTH = 16 ) (
    input  wire i_Clk, i_Rst_L,
    input  wire [1:0] i_SPI_Mode, input wire [7:0] i_Clk_Divider,
    input  wire i_CS_n_Ctrl,
    input  wire [7:0] s_tx_axis_tdata, input wire s_tx_axis_tvalid, output wire s_tx_axis_tready,
    output wire [7:0] m_rx_axis_tdata, output wire m_rx_axis_tvalid, input wire m_rx_axis_tready,
    output wire o_SPI_Clk, input wire i_SPI_MISO, output wire o_SPI_MOSI, output wire o_SPI_CS_n,
    // Thêm để báo trạng thái cho Wrapper
    output wire o_tx_vld, output wire o_tx_rdy_core 
);
    wire tx_vld, tx_rdy_core, rx_dv;
    wire [7:0] tx_byte, rx_byte;
    wire w_Master_TX_DV = tx_rdy_core && tx_vld;

    assign o_tx_vld = tx_vld;
    assign o_tx_rdy_core = tx_rdy_core;

    axis_fifo_spi #(.DEPTH(FIFO_DEPTH)) tx_f (
        .clk(i_Clk), .rst(!i_Rst_L),
        .s_axis_tdata(s_tx_axis_tdata), .s_axis_tvalid(s_tx_axis_tvalid), .s_axis_tready(s_tx_axis_tready),
        .m_axis_tdata(tx_byte), .m_axis_tvalid(tx_vld), .m_axis_tready(w_Master_TX_DV));

    spi_master core (
        .i_Rst_L(i_Rst_L), .i_Clk(i_Clk), .i_SPI_Mode(i_SPI_Mode), .i_Clk_Divider(i_Clk_Divider),
        .i_TX_Byte(tx_byte), .i_TX_DV(w_Master_TX_DV), .o_TX_Ready(tx_rdy_core),
        .o_RX_DV(rx_dv), .o_RX_Byte(rx_byte), .o_SPI_Clk(o_SPI_Clk), .i_SPI_MISO(i_SPI_MISO), .o_SPI_MOSI(o_SPI_MOSI));

    axis_fifo_spi #(.DEPTH(FIFO_DEPTH)) rx_f (
        .clk(i_Clk), .rst(!i_Rst_L),
        .s_axis_tdata(rx_byte), .s_axis_tvalid(rx_dv), .s_axis_tready(),
        .m_axis_tdata(m_rx_axis_tdata), .m_axis_tvalid(m_rx_axis_tvalid), .m_axis_tready(m_rx_axis_tready));

    assign o_SPI_CS_n = i_CS_n_Ctrl;
endmodule
