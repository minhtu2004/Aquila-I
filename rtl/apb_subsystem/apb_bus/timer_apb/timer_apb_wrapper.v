`timescale 1ns / 1ps

module timer_apb_wrapper (
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
    
    output wire        timer_irq
);

    // --- Registers ---
    reg [31:0] r_load;
    reg [15:0] r_prescale;
    reg [3:0]  r_ctrl; 
    reg        r_irq_evt;
    reg        w_zero_det_d; // Register trễ để bắt cạnh Pulse IRQ

    wire [31:0] w_cur_val;
    wire        w_zero_det;

    // --- APB Handshake ---
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // --- Write Logic ---
    wire reg_write = PSEL && PENABLE && PWRITE;
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            r_load <= 32'd0; r_prescale <= 16'd0; r_ctrl <= 4'd0;
        end else if (reg_write) begin
            case (PADDR[4:0])
                5'h04: r_load     <= PWDATA;
                5'h08: r_prescale <= PWDATA[15:0];
                5'h0C: r_ctrl     <= PWDATA[3:0];
            endcase
        end
    end

    // --- Cập nhật bộ trễ bắt cạnh Pulse IRQ (Có Reset để tránh X-propagation) ---
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            w_zero_det_d <= 1'b0;
        end else begin
            w_zero_det_d <= w_zero_det;
        end
    end
    
    // Tín hiệu Pulse nháy 1 clock khi đếm về 0
    wire w_zero_pulse = w_zero_det && !w_zero_det_d; 

    // --- IRQ Management (W1C & Priority Fix) ---
    wire w1c_fire = reg_write && (PADDR[4:0] == 5'h14) && PWDATA[0];
    
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            r_irq_evt <= 1'b0;
        end else begin
            // Ưu tiên Clear (W1C) > Set (Zero Detect)
            if (w1c_fire)
                r_irq_evt <= 1'b0;
            else if (w_zero_det)
                r_irq_evt <= 1'b1;
        end
    end

    // Chọn kiểu ngắt: r_ctrl[3] (0: Level, 1: Pulse)
    assign timer_irq = r_ctrl[2] ? (r_ctrl[3] ? w_zero_pulse : r_irq_evt) : 1'b0;

    // --- Read Logic & PRDATA ---
    reg [31:0] prdata_mux;
    always @(*) begin
        case (PADDR[4:0])
            5'h00: prdata_mux = w_cur_val;
            5'h04: prdata_mux = r_load;
            5'h08: prdata_mux = {16'b0, r_prescale};
            5'h0C: prdata_mux = {28'b0, r_ctrl};
            5'h10: prdata_mux = {31'b0, r_irq_evt};
            default: prdata_mux = 32'd0;
        endcase
    end
    assign PRDATA = (PSEL && !PWRITE) ? prdata_mux : 32'd0;

    // --- Instance Core ---
    timer_core u_core (
        .clk(PCLK), .rst_n(PRESETn),
        .enable(r_ctrl[0]), .auto_reload(r_ctrl[1]),
        .load_val(r_load), .prescale_val(r_prescale),
        .cur_val(w_cur_val), .zero_detected(w_zero_det)
    );

endmodule
