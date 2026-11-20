# Third-party notices

| Files | Upstream and license |
| --- | --- |
| `rtl/master_subsystem/cpu/picorv32.v` | [YosysHQ PicoRV32](https://github.com/YosysHQ/picorv32), copyright 2015 Claire Xenia Wolf. ISC terms are included in the source header. |
| `rtl/apb_subsystem/apb_bus/i2c_apb/i2c_master.v`, `axis_fifo_i2c.v` | [Alex Forencich's verilog-i2c](https://github.com/alexforencich/verilog-i2c), MIT license. Copyright and permission notices are included in the source headers. |
| `rtl/apb_subsystem/apb_bus/uart_apb/uart.v`, `uart_rx.v`, `uart_tx.v` | Adaptations of [Alex Forencich's verilog-uart](https://github.com/alexforencich/verilog-uart). See the MIT notice below. |
| `rtl/apb_subsystem/apb_bus/spi_apb/spi_master.v` | Adaptation of [Nandland SPI Master](https://github.com/nandland/spi-master). See the MIT notice below. |

The RTL regression uses a separate simulation model compatible with the interface of the [VLSIDA SKY130 SRAM macro](https://github.com/VLSIDA/sky130_sram_macros) used in the thesis. The physical macro views and PDK are external dependencies.

## MIT notice for the UART and SPI adaptations

- Copyright (c) 2014-2017 Alex Forencich (UART)
- Copyright (c) 2019 russell-merrick (SPI)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
