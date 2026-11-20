`timescale 1ns / 1ps

module uart_tx # ( parameter DATA_WIDTH = 8 )
(
    input  wire                   clk,
    input  wire                   rst,

    /* AXI stream input */
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    /* UART interface */
    output wire                   txd,

    /* Status */
    output wire                   busy,

    /* Configuration */
    input  wire [15:0]            prescale
);
    // --- KHAI BÁO THANH GHI ---
    reg txd_reg;
    reg busy_reg;
    reg [DATA_WIDTH:0] data_reg;
    reg [18:0] prescale_reg;
    reg [3:0] bit_cnt;

    // --- LOGIC HANDSHAKE & OUTPUT ---
    // Sẵn sàng nhận data mới chỉ khi bit_cnt == 0 và prescale_reg == 0
    assign s_axis_tready = (bit_cnt == 0 && prescale_reg == 0);
    assign txd  = txd_reg;
    assign busy = busy_reg;

    // --- KHỐI LOGIC TRUYỀN DỮ LIỆU ---
    always @(posedge clk) begin
        if (rst) begin
            txd_reg      <= 1'b1; // Idle state của UART là 1
            busy_reg     <= 1'b0;
            prescale_reg <= 19'b0;
            bit_cnt      <= 4'b0;
            data_reg     <= 0;
        end else begin
            if (prescale_reg > 0) begin
                // Đang trong quá trình đếm baudrate cho 1 bit
                prescale_reg <= prescale_reg - 1;
            end else if (bit_cnt == 0) begin
                // Trạng thái nghỉ (Idle)
                busy_reg <= 1'b0;
                // Bắt đầu truyền nếu có data từ FIFO và module đang sẵn sàng
                if (s_axis_tvalid && s_axis_tready) begin
                    prescale_reg <= (prescale << 3) - 1; // Thiết lập chu kỳ bit
                    bit_cnt      <= DATA_WIDTH + 1;     // Start bit + Data bits
                    data_reg     <= {1'b1, s_axis_tdata}; // Load data và Stop bit giả để dịch
                    txd_reg      <= 1'b0;               // Kéo chân TX xuống 0 (Start bit)
                    busy_reg     <= 1'b1;
                end
            end else begin
                // Đang trong quá trình đẩy từng bit ra chân TX
                if (bit_cnt > 1) begin
                    bit_cnt <= bit_cnt - 1;
                    prescale_reg <= (prescale << 3) - 1;
                    // Dịch bit: Đẩy bit thấp nhất ra txd_reg
                    {data_reg, txd_reg} <= {1'b0, data_reg};
                end else begin
                    // Kết thúc bằng Stop bit (mức cao)
                    bit_cnt      <= 0;
                    prescale_reg <= (prescale << 3); // Giữ Stop bit đủ thời gian
                    txd_reg      <= 1'b1;
                end
            end
        end
    end

endmodule
