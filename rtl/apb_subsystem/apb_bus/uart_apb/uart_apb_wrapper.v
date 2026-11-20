`timescale 1ns / 1ps

module uart_apb_wrapper (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PADDR,
    input  wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,
    output wire        uart_irq, 
    input  wire        uart_rx,
    output wire        uart_tx
);

    // --- 1. THANH GHI CẤU HÌNH (Control Registers) ---
    reg [15:0] r_prescale; 
    reg [7:0]  r_ctrl;       // [0]:IE_RX, [1]:IE_OVUN, [2]:IE_TXE

    // --- 2. LATCH SỰ KIỆN NGẮT (Event Latches) ---
    reg        r_irq_rx_evt; 
    reg        r_irq_ovun_evt; 
    reg        r_irq_txe_evt; 

    // --- 3. BỘ ĐỆM PHÁT HIỆN CẠNH (Edge Detection) ---
    reg        rx_valid_d, tx_fifo_empty_d;
    wire       tx_ready, rx_valid, rx_overrun, tx_fifo_empty;
    wire [7:0] rx_data_out;

    // Handshake logic 
    wire tx_fire = PSEL && PENABLE && PWRITE  && (PADDR[4:0] == 5'h00) && tx_ready;
    wire rx_fire = PSEL && PENABLE && !PWRITE && (PADDR[4:0] == 5'h00) && rx_valid;
    wire w1c_fire = PSEL && PENABLE && PWRITE && (PADDR[4:0] == 5'h10); // W1C Register

    // --- 4. APB STALL & READ BUS ---
    assign PREADY  = !(PSEL && PENABLE && ((PWRITE && (PADDR[4:0] == 5'h00) && !tx_ready) || 
                                           (!PWRITE && (PADDR[4:0] == 5'h00) && !rx_valid)));
    assign PSLVERR = 1'b0;

    reg [31:0] r_prdata_mux;
    always @(*) begin
        case (PADDR[4:0])
            5'h00: r_prdata_mux = {24'b0, rx_data_out};
            5'h04: r_prdata_mux = {27'b0, r_irq_ovun_evt, r_irq_txe_evt, rx_valid, tx_ready, tx_fifo_empty};
            5'h08: r_prdata_mux = {24'b0, r_ctrl};
            5'h0C: r_prdata_mux = {16'b0, r_prescale};
            default: r_prdata_mux = 32'b0;
        endcase
    end
    assign PRDATA = (PSEL && !PWRITE) ? r_prdata_mux : 32'b0;

    // --- 5. LOGIC PHÁT HIỆN CẠNH (Edge Detection) ---
    always @(posedge PCLK) begin
        if (!PRESETn) {rx_valid_d, tx_fifo_empty_d} <= 2'b00;
        else           {rx_valid_d, tx_fifo_empty_d} <= {rx_valid, tx_fifo_empty};
    end
    wire rx_rise       = rx_valid && !rx_valid_d;
    wire tx_empty_rise = tx_fifo_empty && !tx_fifo_empty_d;

    // --- 6. BLOCK QUẢN LÝ THANH GHI (Control Logic) ---
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            r_prescale <= 16'd108;
            r_ctrl     <= 8'h0;
        end else if (PSEL && PENABLE && PWRITE) begin
            case (PADDR[4:0])
                5'h08: r_ctrl     <= PWDATA[7:0];
                5'h0C: r_prescale <= PWDATA[15:0];
            endcase
        end
    end

    // --- 7. BLOCK QUẢN LÝ NGẮT (IRQ Logic - Clear over Set) ---
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            r_irq_rx_evt <= 0; r_irq_ovun_evt <= 0; r_irq_txe_evt <= 0;
        end else begin
            // RX Event: Ưu tiên Clear khi đọc (rx_fire) hoặc ghi W1C 
            if (rx_fire || (w1c_fire && PWDATA[0])) r_irq_rx_evt <= 1'b0;
            else if (rx_rise)                        r_irq_rx_evt <= 1'b1;

            // Overrun Event: Clear khi ghi W1C bit 1
            if (w1c_fire && PWDATA[1]) r_irq_ovun_evt <= 1'b0;
            else if (rx_overrun)       r_irq_ovun_evt <= 1'b1;

            // TX Empty Event: Clear khi nạp data mới (tx_fire) hoặc ghi W1C bit 2
            if (tx_fire || (w1c_fire && PWDATA[2])) r_irq_txe_evt <= 1'b0;
            else if (tx_empty_rise)                  r_irq_txe_evt <= 1'b1;
        end
    end
    
    assign uart_irq = (r_irq_rx_evt & r_ctrl[0]) | (r_irq_ovun_evt & r_ctrl[1]) | (r_irq_txe_evt & r_ctrl[2]);

    // --- 8. INSTANCE ---
    uart_fifo uart_inst (
        .clk(PCLK), .rst(~PRESETn),
        .tx_data_in(PWDATA[7:0]), .tx_valid_in(tx_fire), .tx_ready_out(tx_ready),
        .rx_data_out(rx_data_out), .rx_valid_out(rx_valid), .rx_ready_in(rx_fire),
        .rxd(uart_rx), .txd(uart_tx),
        .prescale(r_prescale),
        .overrun_error(rx_overrun),
        .tx_empty(tx_fifo_empty)
    );
endmodule
