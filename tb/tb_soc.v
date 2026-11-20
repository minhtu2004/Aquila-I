`timescale 1ns / 1ps

module tb_soc;

    reg clk;
    reg resetn;

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        resetn = 1'b0;
        repeat (10) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        $display("[%0t] Reset released", $time);
    end

    // =========================================================================
    // DUT signals
    // =========================================================================
    wire trap;
    wire uart_tx;
    wire spi_mosi, spi_cs_n, spi_clk;
    wire spi_miso;

    wire i2c_scl_o, i2c_sda_o, i2c_scl_t, i2c_sda_t;
    wire i2c_scl_i, i2c_sda_i;
    reg  sda_slave_drive;

    assign i2c_scl_i = (!i2c_scl_t && i2c_scl_o == 1'b0) ? 1'b0 : 1'b1;
    assign i2c_sda_i = (!i2c_sda_t && i2c_sda_o == 1'b0) ? 1'b0 :
                       (sda_slave_drive == 1'b0)           ? 1'b0 : 1'b1;

    // =========================================================================
    // I2C Mock Slave
    // =========================================================================
    reg sda_d, scl_d;
    always @(posedge clk) sda_d <= i2c_sda_i;
    always @(posedge clk) scl_d <= i2c_scl_i;

    wire start_cond = (sda_d == 1'b1) && (i2c_sda_i == 1'b0) && (i2c_scl_i == 1'b1);
    wire scl_rise   = (scl_d == 1'b0) && (i2c_scl_i == 1'b1);
    wire scl_fall   = (scl_d == 1'b1) && (i2c_scl_i == 1'b0);

    reg [3:0] i2c_bit_cnt;
    initial begin sda_slave_drive = 1'b1; i2c_bit_cnt = 0; end

    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            i2c_bit_cnt <= 0;
        else if (start_cond)
            i2c_bit_cnt <= 0;
        else if (scl_rise)
            i2c_bit_cnt <= (i2c_bit_cnt == 8) ? 0 : i2c_bit_cnt + 1;
    end

    always @(posedge clk) begin
        if (scl_fall) begin
            if (i2c_bit_cnt == 6 || i2c_bit_cnt == 7 || i2c_bit_cnt == 8)
                sda_slave_drive <= 1'b0;
            else
                sda_slave_drive <= 1'b1;
        end
    end

    // =========================================================================
    // DUT Instance
    // =========================================================================
    soc_top u_dut (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),
        .uart_rx   (1'b1),
        .uart_tx   (uart_tx),
        .spi_clk   (spi_clk),
        .spi_mosi  (spi_mosi),
        .spi_cs_n  (spi_cs_n),
        .spi_miso  (spi_miso),
        .i2c_scl_i (i2c_scl_i),
        .i2c_sda_i (i2c_sda_i),
        .i2c_scl_o (i2c_scl_o),
        .i2c_scl_t (i2c_scl_t),
        .i2c_sda_o (i2c_sda_o),
        .i2c_sda_t (i2c_sda_t)
    );

    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial if ($test$plusargs("waves")) begin
        $dumpfile("build/soc.vcd");
        $dumpvars(0, tb_soc);
    end


    // =========================================================================
    // Hierarchical Probes
    // =========================================================================
    wire [31:0] cpu_araddr  = u_dut.u_master.cpu_axi_araddr;
    wire [31:0] irq_flag    = u_dut.u_master.u_ram.u_sram.mem[4];  // 
    wire [31:0] global_zero = u_dut.u_master.u_ram.u_sram.mem[0];  // 
    wire [31:0] irq_seen_count = u_dut.u_master.u_ram.u_sram.mem[5];  // 
    //wire [31:0] global_zero      = u_dut.u_master.u_ram.u_sram.mem[0];   // 0x00010000
wire [31:0] test_stage       = u_dut.u_master.u_ram.u_sram.mem[2];   // 0x00010008
wire [31:0] fail_code        = u_dut.u_master.u_ram.u_sram.mem[3];   // 0x0001000C

wire [31:0] timer_result     = u_dut.u_master.u_ram.u_sram.mem[6];   // 0x00010018
wire [31:0] spi_result       = u_dut.u_master.u_ram.u_sram.mem[7];   // 0x0001001C
wire [31:0] i2c_result       = u_dut.u_master.u_ram.u_sram.mem[8];   // 0x00010020
wire [31:0] timer_irq_result = u_dut.u_master.u_ram.u_sram.mem[9];   // 0x00010024
wire [31:0] dma_result       = u_dut.u_master.u_ram.u_sram.mem[10];  // 0x00010028
wire [31:0] crc_test_result  = u_dut.u_master.u_ram.u_sram.mem[11];  // 0x0001002C
wire [31:0] aes_test_result  = u_dut.u_master.u_ram.u_sram.mem[12];  // 0x00010030
wire [31:0] irq_test_result  = u_dut.u_master.u_ram.u_sram.mem[13];  // 0x00010034
wire [31:0] err_test_result  = u_dut.u_master.u_ram.u_sram.mem[14];  // 0x00010038

wire [31:0] dbg_dma_status   = u_dut.u_master.u_ram.u_sram.mem[15];  // 0x0001003C
wire [31:0] dbg_dma_error    = u_dut.u_master.u_ram.u_sram.mem[16];  // 0x00010040
wire [31:0] dbg_crc_apb      = u_dut.u_master.u_ram.u_sram.mem[17];  // 0x00010044
wire [31:0] dbg_crc_ram      = u_dut.u_master.u_ram.u_sram.mem[18];  // 0x00010048
wire [31:0] dbg_aes_status   = u_dut.u_master.u_ram.u_sram.mem[19];  // 0x0001004C
wire [31:0] dbg_irq_pending  = u_dut.u_master.u_ram.u_sram.mem[20];  // 0x00010050
wire [31:0] dbg_irq_mask     = u_dut.u_master.u_ram.u_sram.mem[21];  // 0x00010054
wire [31:0] dbg_spi_rx       = u_dut.u_master.u_ram.u_sram.mem[22];  // 0x00010058
wire [31:0] dbg_i2c_sts      = u_dut.u_master.u_ram.u_sram.mem[23];  // 0x0001005C

wire [31:0] aes_ct0          = u_dut.u_master.u_ram.u_sram.mem[24];  // 0x00010060
wire [31:0] aes_ct1          = u_dut.u_master.u_ram.u_sram.mem[25];  // 0x00010064
wire [31:0] aes_ct2          = u_dut.u_master.u_ram.u_sram.mem[26];  // 0x00010068
wire [31:0] aes_ct3          = u_dut.u_master.u_ram.u_sram.mem[27];  // 0x0001006C
wire [31:0] aes_ct4          = u_dut.u_master.u_ram.u_sram.mem[28];  // 0x00010070
wire [31:0] aes_ct5          = u_dut.u_master.u_ram.u_sram.mem[29];  // 0x00010074
wire [31:0] aes_ct6          = u_dut.u_master.u_ram.u_sram.mem[30];  // 0x00010078
wire [31:0] aes_ct7          = u_dut.u_master.u_ram.u_sram.mem[31];  // 0x0001007C 

    // =========================================================================
    // Firmware completion and error monitor
    // =========================================================================
    localparam [31:0] PASS_MARKER = 32'h0000_AAAA;
    localparam [31:0] DONE_STAGE  = 32'h0000_00FF;

    always @(posedge clk) begin
        if (resetn) begin
            if (trap !== 1'b0)
                $fatal(1, "CPU trap or invalid trap signal: stage=0x%08h last_fetch=0x%08h",
                       test_stage, cpu_araddr);
            if (fail_code != 32'h0)
                $fatal(1, "Firmware failed: stage=0x%08h fail_code=0x%08h",
                       test_stage, fail_code);
            if (global_zero === PASS_MARKER && test_stage === DONE_STAGE &&
                fail_code === 32'h0) begin
                if (dbg_i2c_sts[2] !== 1'b0 || dbg_i2c_sts[0] !== 1'b1)
                    $fatal(1, "Expected an acknowledged I2C write: status=0x%08h", dbg_i2c_sts);
                $display("AQUILA-I RTL PASS: marker=0x%08h stage=0x%08h fail_code=0x%08h at %0t",
                         global_zero, test_stage, fail_code, $time);
                $finish;
            end
        end
    end

    // =========================================================================
    // UART TX Decoder
    // =========================================================================
    integer uart_bit_period = 8640;
    reg [7:0] uart_rx_byte;
    integer   uart_bit_cnt;
    string uart_line = "";

    initial begin
        uart_rx_byte = 0;
        forever begin
            @(negedge uart_tx);
            #(uart_bit_period + uart_bit_period/2);
            uart_bit_cnt = 0;
            repeat (8) begin
                uart_rx_byte = {uart_tx, uart_rx_byte[7:1]};
                uart_bit_cnt = uart_bit_cnt + 1;
                #(uart_bit_period);
            end
            if (uart_rx_byte == 8'h0d) begin
            // bỏ qua CR
            end else if (uart_rx_byte == 8'h0a) begin
               $display("[%0t] UART LINE: %s", $time, uart_line);
               uart_line = "";
            end else begin
               uart_line = {uart_line, uart_rx_byte};
            end
            //$display("[%0t] UART RX: 0x%02X '%c'", $time, uart_rx_byte, uart_rx_byte);
        end
    end

    // =========================================================================
    // Timer Monitor
    // =========================================================================
    reg timer_irq_d;
    always @(posedge clk) timer_irq_d <= u_dut.u_apb.u_apb_subsystem.u_timer.timer_irq;

    realtime t_start, t_delta;
    integer timer_irq_cnt = 0;

    always @(posedge clk) begin
        if (u_dut.u_apb.u_apb_subsystem.u_timer.timer_irq && !timer_irq_d) begin
            $display("[%0t] TIMER IRQ rising edge", $time);
            if (timer_irq_cnt == 1) t_start = $realtime;
            if (timer_irq_cnt == 2) begin
                t_delta = $realtime - t_start;
                //$display("[%0t] TIMER period = %0t ns", $time, t_delta);
            end
            timer_irq_cnt = timer_irq_cnt + 1;
        end
    end

    // =========================================================================
    // SPI Monitor
    // =========================================================================
    reg spi_irq_d;
    always @(posedge clk) spi_irq_d <= u_dut.u_apb.u_apb_subsystem.u_spi.o_spi_irq;

    /*always @(posedge clk) begin
        if (u_dut.u_apb.u_apb_subsystem.u_spi.o_spi_irq && !spi_irq_d)
            $display("[%0t] SPI IRQ rising edge", $time);
    end*/

    assign #6 spi_miso = spi_mosi;

    // =========================================================================
    // I2C Monitor
    // =========================================================================
    /*always @(posedge clk) begin
        if (start_cond)
            $display("[%0t] I2C START detected", $time);
    end*/

    // =========================================================================
    // IRQ Controller Monitor
    // =========================================================================
    wire [31:0] irq_out     = u_dut.irq_out;
    wire [31:0] irq_pending = u_dut.u_apb.u_apb_subsystem.u_irq_ctrl.r_pending;
    wire [31:0] irq_mask    = u_dut.u_apb.u_apb_subsystem.u_irq_ctrl.r_mask;
    
    

    reg [31:0] irq_out_d;
    always @(posedge clk) irq_out_d <= irq_out;

    always @(posedge clk) begin
        if (irq_out && !irq_out_d)
            $display("[%0t] IRQ_OUT rising: 0x%08X pending=0x%08X mask=0x%08X",
                     $time, irq_out, irq_pending, irq_mask);
    end

    always @(posedge clk) begin
        if (!irq_out && irq_out_d)
            $display("[%0t] IRQ_OUT falling (cleared)", $time);
    end
    
    //////////////////////// đã xóa bớt probe, có sao lưu rồi,
    //PROBE start/////////// nếu ní thấy bao nhiêu đây không đủ probe, thì lấy ra lại,
    //////////////////////// còn không thì thôi
    
/*always @(posedge clk) begin
    if (u_dut.u_apb.u_apb_subsystem.u_irq_ctrl.psel &&
        u_dut.u_apb.u_apb_subsystem.u_irq_ctrl.penable &&
        u_dut.u_apb.u_apb_subsystem.u_irq_ctrl.pwrite)
        $display("[%0t] IRQ W1C addr=0x%02X data=0x%08X",
                 $time,
                 u_dut.u_apb.u_apb_subsystem.u_irq_ctrl.paddr,
                 u_dut.u_apb.u_apb_subsystem.u_irq_ctrl.pwdata);
end*/
    //////////////////////////////////////
    //PROBE end //////////////////////////
    //////////////////////////////////////

    // =========================================================================
    // DMA Monitor
    // =========================================================================
    wire        dma_done_irq   = u_dut.dma_done_irq;
    wire [3:0]  dma_state      = u_dut.u_master.u_dma.state;
    wire [31:0] dma_axi_araddr = u_dut.u_master.dma_axi_araddr;
    wire [31:0] dma_axi_awaddr = u_dut.u_master.dma_axi_awaddr;
    wire        dma_arvalid    = u_dut.u_master.dma_axi_arvalid;
    wire        dma_arready    = u_dut.u_master.dma_axi_arready;
    wire        dma_awvalid    = u_dut.u_master.dma_axi_awvalid;
    wire        dma_awready    = u_dut.u_master.dma_axi_awready;

    // DMA AXI read transactions
    always @(posedge clk) begin
        if (dma_arvalid && dma_arready)
            $display("[%0t] DMA RD addr=0x%08X", $time, dma_axi_araddr);
    end

    // DMA AXI write transactions
    always @(posedge clk) begin
        if (dma_awvalid && dma_awready)
            $display("[%0t] DMA WR addr=0x%08X", $time, dma_axi_awaddr);
    end

    // DMA done IRQ
    reg dma_done_irq_d;
    always @(posedge clk) dma_done_irq_d <= dma_done_irq;
    always @(posedge clk) begin
        if (dma_done_irq && !dma_done_irq_d)
            $display("[%0t] DMA DONE IRQ fired (state=%0d)", $time, dma_state);
    end
    
    // =========================================================================
    // Watchdog (20 ms of simulated time at the RTL test clock)
    // =========================================================================
    integer max_cycles;

    initial begin
        max_cycles = 2_000_000;
        if ($value$plusargs("max_cycles=%d", max_cycles) && !(max_cycles > 0))
            $fatal(1, "max_cycles must be a positive integer");
        @(posedge resetn);
        // Sample after the completion monitor has evaluated the last cycle.
        repeat (max_cycles) @(negedge clk);
        $fatal(1, "Simulation timeout after %0d cycles: stage=0x%08h marker=0x%08h fail_code=0x%08h",
               max_cycles, test_stage, global_zero, fail_code);
    end

endmodule
