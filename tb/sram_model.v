`timescale 1ns / 1ps

// Simulation model for the interface used by the Aquila-I SRAM wrapper.
// Port 0 accepts byte-enabled writes and registered reads. Port 1 is read-only.
module sky130_sram_2kbyte_1rw1r_32x512_8 #(
    parameter VERBOSE = 0
) (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [ 3:0] wmask0,
    input  wire [ 8:0] addr0,
    input  wire [31:0] din0,
    output reg  [31:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [ 8:0] addr1,
    output reg  [31:0] dout1
);
    reg [31:0] mem [0:511];
    integer address;
    integer byte_lane;

    initial begin
        for (address = 0; address < 512; address = address + 1)
            mem[address] = 32'h0;
    end

    always @(posedge clk0) begin
        if (!csb0) begin
            if (web0) begin
                dout0 <= mem[addr0];
            end else begin
                for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
                    if (wmask0[byte_lane])
                        mem[addr0][8*byte_lane +: 8] <= din0[8*byte_lane +: 8];
            end
            if (VERBOSE)
                $display("SRAM port 0 %s, word 0x%03h", web0 ? "read" : "write", addr0);
        end
    end

    always @(posedge clk1) begin
        if (!csb1)
            dout1 <= mem[addr1];
    end
endmodule
