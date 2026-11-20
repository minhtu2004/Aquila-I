`timescale 1ns / 1ps

module timer_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        auto_reload,
    input  wire [31:0] load_val,
    input  wire [15:0] prescale_val,
    output wire [31:0] cur_val,
    output wire        zero_detected
);

    reg [31:0] r_cur;
    reg [15:0] r_prescale_cnt;
    reg        enable_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) enable_d <= 1'b0;
        else        enable_d <= enable;
    end
    wire enable_edge = enable && !enable_d;

    wire prescale_tick = (r_prescale_cnt == 16'd0);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_prescale_cnt <= 16'd0;
        end else if (enable) begin
            if (prescale_tick) r_prescale_cnt <= prescale_val;
            else               r_prescale_cnt <= r_prescale_cnt - 1;
        end else begin
            r_prescale_cnt <= prescale_val;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_cur <= 32'd0;
        end else if (enable_edge) begin
            r_cur <= load_val;
        end else if (enable && prescale_tick) begin
            if (r_cur != 32'd0) begin
                r_cur <= r_cur - 1;
            end else if (auto_reload) begin
                r_cur <= load_val;
            end
            // Nếu không auto_reload, nó sẽ giữ nguyên ở 0 và không kích zero_detected nữa
        end
    end

    assign cur_val = r_cur;
    
    // FIX QUAN TRỌNG: Chỉ báo zero khi bộ đếm đang ở 1 và chuẩn bị về 0
    // Điều này tạo ra một xung (pulse) duy nhất 1-clock
    assign zero_detected = (r_cur == 32'd1) && prescale_tick && enable;

endmodule
