`timescale 1ns / 1ps

module uart_rx # ( parameter DATA_WIDTH = 8 )
(
    input  wire                   clk,
    input  wire                   rst,

    /* AXI stream output */
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,

    /* UART interface */
    input  wire                   rxd,

    /* Status */
    output wire                   busy,
    output wire                   overrun_error,
    output wire                   frame_error,

    /* Configuration */
    input  wire [15:0]            prescale
);

    // --- 1. CHỐNG NHIỄU (3-STAGE CDC SYNCHRONIZER) ---
    // Tín hiệu rxd từ ngoài chip rất dễ gây lỗi Metastability
    reg [2:0] rxd_sync;
    always @(posedge clk) begin
        if (rst) rxd_sync <= 3'b111; // UART Idle là mức cao
        else     rxd_sync <= {rxd_sync[1:0], rxd};
    end
    wire rxd_stable = rxd_sync[2]; // Dùng tín hiệu đã ổn định qua 3 tầng FF

    // --- 2. KHAI BÁO THANH GHI ---
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg;
    reg m_axis_tvalid_reg;
    reg busy_reg;
    reg overrun_error_reg;
    reg frame_error_reg;
    reg [DATA_WIDTH-1:0] data_reg;
    reg [18:0] prescale_reg;
    reg [3:0] bit_cnt;

    // Gán output từ register
    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign busy          = busy_reg;
    assign overrun_error = overrun_error_reg;
    assign frame_error   = frame_error_reg;

    // --- 3. LOGIC NHẬN DỮ LIỆU ---
    always @(posedge clk) begin
        if (rst) begin
            m_axis_tdata_reg  <= 0;
            m_axis_tvalid_reg <= 0;
            busy_reg          <= 0;
            overrun_error_reg <= 0;
            frame_error_reg   <= 0;
            prescale_reg      <= 0;
            bit_cnt           <= 0;
            data_reg          <= 0;
        end else begin
            // Clear Valid khi có handshake thành công 
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid_reg <= 0;
            end

            if (prescale_reg > 0) begin
                prescale_reg <= prescale_reg - 1;
            end else if (bit_cnt > 0) begin
                // Trạng thái đang nhận bit
                if (bit_cnt > DATA_WIDTH+1) begin
                    // Kiểm tra Start bit (phải là 0)
                    if (!rxd_stable) begin
                        bit_cnt <= bit_cnt - 1;
                        prescale_reg <= (prescale << 3)-1;
                    end else begin
                        bit_cnt <= 0; // Nhiễu, hủy bỏ
                    end
                end else if (bit_cnt > 1) begin
                    // Nhận các bit dữ liệu
                    bit_cnt <= bit_cnt - 1;
                    prescale_reg <= (prescale << 3)-1;
                    data_reg <= {rxd_stable, data_reg[DATA_WIDTH-1:1]};
                end else if (bit_cnt == 1) begin
                    // Xử lý Stop bit (phải là 1)
                    bit_cnt <= bit_cnt - 1;
                    if (rxd_stable) begin
                        m_axis_tdata_reg  <= data_reg;
                        m_axis_tvalid_reg <= 1;
                        // Báo lỗi Overrun nếu byte cũ chưa được lấy đi
                        overrun_error_reg <= m_axis_tvalid_reg; 
                    end else begin
                        frame_error_reg   <= 1;
                    end
                end
            end else begin
                // Trạng thái chờ Start bit
                busy_reg <= 0;
                if (!rxd_stable) begin
                    prescale_reg <= (prescale << 2)-2;
                    bit_cnt      <= DATA_WIDTH+2;
                    data_reg     <= 0;
                    busy_reg     <= 1;
                end
            end
        end
    end

endmodule
