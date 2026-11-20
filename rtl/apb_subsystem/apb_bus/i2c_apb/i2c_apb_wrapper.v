`timescale 1ns / 1ps

module i2c_apb_wrapper # (
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    input  wire pclk, presetn, psel, penable, pwrite,
    input  wire [ADDR_WIDTH-1:0] paddr, input wire [DATA_WIDTH-1:0] pwdata,
    output reg  [DATA_WIDTH-1:0] prdata,
    output wire pready, pslverr,
    output wire o_i2c_irq,

    input  wire scl_i, output wire scl_o, output wire scl_t,
    input  wire sda_i, output wire sda_o, output wire sda_t
);
    reg [6:0]  reg_i2c_addr;
    reg [15:0] reg_prescale;
    reg [7:0]  reg_ctrl;
    reg        reg_cmd_valid;

    reg [2:0]  r_int_en;
    reg [2:0]  r_int_sts;

    wire [7:0] i2c_rx_data;
    wire i2c_rx_valid, i2c_busy, i2c_missed_ack, tx_fifo_ready;
    reg  i2c_busy_d1, i2c_rx_valid_d1;

    wire can_config = !i2c_busy;
    assign pready  = (psel && pwrite && (paddr[7:0] == 8'h0C)) ? tx_fifo_ready : 1'b1;
    assign pslverr = 1'b0;
    assign o_i2c_irq = |(r_int_sts & r_int_en);

    // --- IRQ logic ---
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_int_sts <= 3'b0; i2c_busy_d1 <= 1'b0; i2c_rx_valid_d1 <= 1'b0;
        end else begin
            i2c_busy_d1 <= i2c_busy; i2c_rx_valid_d1 <= i2c_rx_valid;
            if (!i2c_busy && i2c_busy_d1 && r_int_en[0])         r_int_sts[0] <= 1'b1;
            if (i2c_rx_valid && !i2c_rx_valid_d1 && r_int_en[1]) r_int_sts[1] <= 1'b1;
            if (i2c_missed_ack && r_int_en[2])                    r_int_sts[2] <= 1'b1;
            if (psel && penable && pwrite && (paddr[7:0] == 8'h1C))
                r_int_sts <= r_int_sts & ~pwdata[2:0];
        end
    end

    // --- Write path ---
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_i2c_addr <= 7'd0; reg_prescale <= 16'd250; reg_ctrl <= 8'd0;
            reg_cmd_valid <= 1'b0; r_int_en <= 3'b0;
        end else begin
            reg_cmd_valid <= 1'b0;
            if (psel && penable && pwrite) begin
                case (paddr[7:0])
                    8'h00: begin reg_cmd_valid <= 1'b1; reg_ctrl <= pwdata[7:0]; end
                    8'h04: if (can_config) reg_i2c_addr <= pwdata[6:0];
                    8'h08: if (can_config) reg_prescale <= pwdata[15:0];
                    8'h18: begin r_int_en <= pwdata[2:0]; r_int_sts <= 3'b0; end
                endcase
            end
        end
    end

    // --- Read path (combinational — fix registered read lag) ---
    always @(*) begin
        case (paddr[7:0])
            8'h00:   prdata = {24'd0, reg_ctrl};
            8'h04:   prdata = {25'd0, reg_i2c_addr};
            8'h08:   prdata = {16'd0, reg_prescale};
            8'h10:   prdata = {24'd0, i2c_rx_data};
            8'h14:   prdata = {28'd0, 2'b0, i2c_missed_ack, i2c_busy};
            8'h18:   prdata = {29'd0, r_int_en};
            8'h1C:   prdata = {29'd0, r_int_sts};
            default: prdata = 32'hDEADBEEF;
        endcase
    end

    // --- 2-flop synchronizers for external I2C inputs ---
    // I2C is much slower than pclk, so 2-cycle sync latency is acceptable.
    reg scl_i_meta, scl_i_sync;
    reg sda_i_meta, sda_i_sync;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            scl_i_meta <= 1'b1;
            scl_i_sync <= 1'b1;
            sda_i_meta <= 1'b1;
            sda_i_sync <= 1'b1;
        end else begin
            scl_i_meta <= scl_i;
            scl_i_sync <= scl_i_meta;
            sda_i_meta <= sda_i;
            sda_i_sync <= sda_i_meta;
        end
    end

    // --- Core I2C ---
    i2c_master_top #(.FIFO_DEPTH(64)) i2c_sys_inst (
        .clk(pclk), .rst(!presetn),
        .s_axis_data_tdata(pwdata[7:0]),
        .s_axis_data_tvalid(psel && penable && pwrite && (paddr[7:0] == 8'h0C)),
        .s_axis_data_tready(tx_fifo_ready),
        .s_axis_data_tlast(pwdata[8]),
        .s_axis_cmd_address(reg_i2c_addr),
        .s_axis_cmd_start(reg_ctrl[0]), .s_axis_cmd_read(reg_ctrl[2]),
        .s_axis_cmd_write(reg_ctrl[3]), .s_axis_cmd_stop(reg_ctrl[5]),
        .s_axis_cmd_valid(reg_cmd_valid),
        .m_axis_data_tdata(i2c_rx_data), .m_axis_data_tvalid(i2c_rx_valid),
        .m_axis_data_tready(1'b1),
        .scl_i(scl_i_sync), .scl_o(scl_o), .scl_t(scl_t),
        .sda_i(sda_i_sync), .sda_o(sda_o), .sda_t(sda_t),
        .prescale(reg_prescale), .busy(i2c_busy), .missed_ack(i2c_missed_ack)
    );
endmodule
