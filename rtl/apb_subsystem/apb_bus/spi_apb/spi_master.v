module spi_master (
   input        i_Rst_L,     
   input        i_Clk,       
   input [1:0]  i_SPI_Mode,          
   input [7:0]  i_Clk_Divider,       
   input [7:0]  i_TX_Byte,        
   input        i_TX_DV,          
   output reg   o_TX_Ready,       
   output reg   o_RX_DV,     
   output reg [7:0] o_RX_Byte,   
   output reg   o_SPI_Clk,
   input        i_SPI_MISO,
   output reg   o_SPI_MOSI
);
  wire w_CPOL = (i_SPI_Mode == 2'd2) | (i_SPI_Mode == 2'd3);
  wire w_CPHA = (i_SPI_Mode == 2'd1) | (i_SPI_Mode == 2'd3);
  wire [8:0] w_Div = (i_Clk_Divider == 8'd0) ? 9'd1 : {1'b0, i_Clk_Divider};

  reg [8:0] r_SPI_Clk_Count; 
  reg r_SPI_Clk;
  reg [4:0] r_SPI_Clk_Edges;
  reg r_Leading_Edge;
  reg r_Trailing_Edge;
  reg r_TX_DV;
  reg [7:0] r_TX_Byte;
  reg [2:0] r_RX_Bit_Count;
  reg [2:0] r_TX_Bit_Count;

  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (~i_Rst_L) begin
      o_TX_Ready      <= 1'b0;
      r_SPI_Clk_Edges <= 5'd0;
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      r_SPI_Clk       <= 1'b0;
      o_SPI_Clk       <= 1'b0;
      r_SPI_Clk_Count <= 9'd0;
    end else begin
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      if (i_TX_DV) begin
        o_TX_Ready      <= 1'b0;
        r_SPI_Clk_Edges <= 5'd16;
        r_SPI_Clk       <= w_CPOL;
        o_SPI_Clk       <= w_CPOL;
        r_SPI_Clk_Count <= 9'd0;
      end else if (r_SPI_Clk_Edges > 5'd0) begin
        o_TX_Ready <= 1'b0;
        // Ép kiểu 9-bit để Verilator không "la"
        if (r_SPI_Clk_Count == ((w_Div << 1) - 9'd1)) begin
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 5'd1;
          r_Trailing_Edge <= 1'b1;
          r_SPI_Clk_Count <= 9'd0;
          r_SPI_Clk       <= ~r_SPI_Clk;
          o_SPI_Clk       <= ~r_SPI_Clk;
        end else if (r_SPI_Clk_Count == (w_Div - 9'd1)) begin
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 5'd1;
          r_Leading_Edge  <= 1'b1;
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 9'd1;
          r_SPI_Clk       <= ~r_SPI_Clk;
          o_SPI_Clk       <= ~r_SPI_Clk;
        end else begin
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 9'd1;
        end
      end else begin
        o_TX_Ready <= 1'b1;
        r_SPI_Clk  <= w_CPOL;
        o_SPI_Clk  <= w_CPOL;
      end
    end
  end

  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (~i_Rst_L) begin
      r_TX_Byte <= 8'h00;
      r_TX_DV   <= 1'b0;
    end else begin
      r_TX_DV <= i_TX_DV;
      if (i_TX_DV) r_TX_Byte <= i_TX_Byte;
    end
  end

  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (~i_Rst_L) begin
      o_SPI_MOSI     <= 1'b0;
      r_TX_Bit_Count <= 3'b111;
    end else begin
      if (o_TX_Ready) begin
        r_TX_Bit_Count <= 3'b111;
      end else if (r_TX_DV & ~w_CPHA) begin
        o_SPI_MOSI     <= r_TX_Byte[3'b111];
        r_TX_Bit_Count <= 3'b110;
      end else if ((r_Leading_Edge & w_CPHA) | (r_Trailing_Edge & ~w_CPHA)) begin
        r_TX_Bit_Count <= r_TX_Bit_Count - 3'd1;
        o_SPI_MOSI     <= r_TX_Byte[r_TX_Bit_Count];
      end
    end
  end

  always @(posedge i_Clk or negedge i_Rst_L) begin
    if (~i_Rst_L) begin
      o_RX_Byte      <= 8'h00;
      o_RX_DV        <= 1'b0;
      r_RX_Bit_Count <= 3'b111;
    end else begin
      o_RX_DV   <= 1'b0;
      if (o_TX_Ready) begin
        r_RX_Bit_Count <= 3'b111;
      end else if ((r_Leading_Edge & ~w_CPHA) | (r_Trailing_Edge & w_CPHA)) begin
        o_RX_Byte[r_RX_Bit_Count] <= i_SPI_MISO;
        r_RX_Bit_Count            <= r_RX_Bit_Count - 3'd1;
        if (r_RX_Bit_Count == 3'b000) o_RX_DV <= 1'b1;
      end
    end
  end
endmodule
