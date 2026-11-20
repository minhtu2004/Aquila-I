`timescale 1ns / 1ps
// =============================================================================
// irq_controller.v
// Flat 32-bit IRQ controller — APB slave
// =============================================================================
module irq_controller #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter N_IRQ      = 32
) (
    input  wire                  pclk,
    input  wire                  presetn,

    // APB slave
    input  wire [ADDR_WIDTH-1:0] paddr,
    input  wire                  psel,
    input  wire                  penable,
    input  wire                  pwrite,
    input  wire [DATA_WIDTH-1:0] pwdata,
    output reg  [DATA_WIDTH-1:0] prdata,
    output wire                  pready,
    output wire                  pslverr,

    // Raw IRQ from peripherals
    input  wire [N_IRQ-1:0]      raw_irq,

    // To CPU
    output wire [N_IRQ-1:0]      irq_out
);

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    reg [N_IRQ-1:0] r_pending;
    reg [N_IRQ-1:0] r_mask;
    reg [N_IRQ-1:0] raw_d1;
    // irq_out = combinational r_pending & r_mask

    // Edge detect
    wire [N_IRQ-1:0] rising = raw_irq & ~raw_d1;

    // APB write detect
    wire apb_write = psel && penable && pwrite;

    wire [N_IRQ-1:0] w1c_clear =
        (apb_write && paddr[7:0] == 8'h00) ? pwdata[N_IRQ-1:0] : {N_IRQ{1'b0}};

    wire [N_IRQ-1:0] w1s_force =
        (apb_write && paddr[7:0] == 8'h0C) ? pwdata[N_IRQ-1:0] : {N_IRQ{1'b0}};

    //NEW: next state
    wire [N_IRQ-1:0] next_pending;
    //assign next_pending = (r_pending | rising | w1s_force) & ~w1c_clear;
    assign next_pending = (r_pending & ~w1c_clear) | rising | w1s_force;

    
    //wire [N_IRQ-1:0] next_mask = (apb_write && paddr[7:0] == 8'h04) ? pwdata[N_IRQ-1:0] : r_mask;

    // Sequential logic
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_pending <= {N_IRQ{1'b0}};
            r_mask    <= {N_IRQ{1'b0}};
            raw_d1    <= {N_IRQ{1'b0}};

        end else begin
            raw_d1 <= raw_irq;

            // update pending
            r_pending <= next_pending;


            // mask write
            if (apb_write && paddr[7:0] == 8'h04) begin
                r_mask <= pwdata[N_IRQ-1:0];
            end
        end
    end

    // IRQ output — combinational (trực tiếp từ r_pending & r_mask)
    assign irq_out = r_pending & r_mask;

    // Read path
    always @(*) begin
        case (paddr[7:0])
            8'h00:   prdata = r_pending;
            8'h04:   prdata = r_mask;
            8'h08:   prdata = raw_irq;
            8'h0C:   prdata = {DATA_WIDTH{1'b0}};
            8'h10:   prdata = r_pending & r_mask; // combinational STATUS (no lag)
            default: prdata = 32'hDEADBEEF;
        endcase
    end
endmodule
