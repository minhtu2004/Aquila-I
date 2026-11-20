`timescale 1ns / 1ps
module spi_apb_wrapper (
    input  wire pclk, presetn, psel, penable, pwrite,
    input  wire [7:0] paddr, input wire [31:0] pwdata,
    output reg [31:0] prdata, output wire pready, pslverr,
    output wire o_spi_irq,
    output wire o_SPI_Clk, o_SPI_MOSI, o_SPI_CS_n, input wire i_SPI_MISO
);
    reg [7:0] r_tx_data; reg r_tx_vld, r_rx_rdy;
    reg [1:0] r_mode; reg [7:0] r_div; reg r_cs_n;
    reg [1:0] r_int_en, r_int_sts;
    wire [7:0] w_rx_data; wire w_rx_vld, w_tx_rdy_bus, w_tx_vld_f, w_tx_rdy_core;
    reg  w_rx_vld_d1, w_tx_rdy_core_d1;

    wire can_config = w_tx_rdy_core && !w_tx_vld_f;
    assign o_spi_irq = |(r_int_sts & r_int_en);

    // --- IRQ logic ---
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_int_sts <= 2'b0; w_rx_vld_d1 <= 1'b0; w_tx_rdy_core_d1 <= 1'b1;
        end else begin
            w_rx_vld_d1 <= w_rx_vld; w_tx_rdy_core_d1 <= w_tx_rdy_core;
            if (w_rx_vld && !w_rx_vld_d1 && r_int_en[1]) r_int_sts[1] <= 1'b1;
            if (w_tx_rdy_core && !w_tx_rdy_core_d1 && !w_tx_vld_f && r_int_en[0]) r_int_sts[0] <= 1'b1;
            if (psel && penable && pwrite && (paddr == 8'h14))
                r_int_sts <= r_int_sts & ~pwdata[1:0];
        end
    end

    assign pready  = (psel && pwrite && (paddr == 8'h00)) ? w_tx_rdy_bus : 1'b1;
    assign pslverr = 1'b0;

    // --- Write path (registered) ---
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_mode <= 2'd0; r_div <= 8'd4; r_cs_n <= 1'b1;
            r_tx_vld <= 1'b0; r_rx_rdy <= 1'b0;
            r_int_en <= 2'b0; r_tx_data <= 8'h00;
        end else begin
            r_tx_vld <= 1'b0; r_rx_rdy <= 1'b0;
            if (psel && penable && pwrite) begin
                case (paddr[7:0])
                    8'h00: begin r_tx_data <= pwdata[7:0]; r_tx_vld <= 1'b1; end
                    8'h08: begin
                        r_cs_n <= pwdata[16];
                        if (can_config) begin r_mode <= pwdata[1:0]; r_div <= pwdata[15:8]; end
                    end
                    8'h10: begin r_int_en <= pwdata[1:0]; r_int_sts <= 2'b0; end
                    default: ;
                endcase
            end else if (psel && penable && !pwrite && paddr[7:0] == 8'h04) begin
                r_rx_rdy <= 1'b1; // pop FIFO khi đọc RX
            end
        end
    end

    // --- Read path (combinational — fix registered read lag) ---
    always @(*) begin
        case (paddr[7:0])
            8'h04:    prdata = {24'd0, w_rx_data};
            8'h08:    prdata = {15'd0, r_cs_n, r_div, 6'd0, r_mode};
            8'h0C:    prdata = {30'd0, w_rx_vld, w_tx_rdy_bus};
            8'h10:    prdata = {30'd0, r_int_en};
            8'h14:    prdata = {30'd0, r_int_sts};
            default:  prdata = 32'hDEADBEEF;
        endcase
    end

    spi_top #(.FIFO_DEPTH(16)) u_top (
        .i_Clk(pclk), .i_Rst_L(presetn), .i_SPI_Mode(r_mode), .i_Clk_Divider(r_div),
        .i_CS_n_Ctrl(r_cs_n), .s_tx_axis_tdata(r_tx_data), .s_tx_axis_tvalid(r_tx_vld),
        .s_tx_axis_tready(w_tx_rdy_bus), .m_rx_axis_tdata(w_rx_data), .m_rx_axis_tvalid(w_rx_vld),
        .m_rx_axis_tready(r_rx_rdy), .o_SPI_Clk(o_SPI_Clk), .i_SPI_MISO(i_SPI_MISO),
        .o_SPI_MOSI(o_SPI_MOSI), .o_SPI_CS_n(o_SPI_CS_n), .o_tx_vld(w_tx_vld_f),
        .o_tx_rdy_core(w_tx_rdy_core));

endmodule
