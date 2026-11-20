RISCV_PREFIX ?= riscv64-unknown-elf-
IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python3
VVP_ARGS ?=

FW_SOURCES := firmware/start.s firmware/main.c
FW_LINKER := firmware/sections.lds
FW_FLAGS := -march=rv32i -mabi=ilp32 -nostdlib -O0
HEX2ROM := rtl/master_subsystem/rom/Hex2rom.py
RTL_SOURCES := $(sort $(shell find rtl -type f -name '*.v'))
TB_SOURCES := tb/tb_soc.v tb/sram_model.v

.DELETE_ON_ERROR:
.PHONY: test sim fw clean

test: build/tb_soc.vvp
	$(VVP) -N $< $(VVP_ARGS)

sim: test

fw: build/rom.v

build:
	mkdir -p $@

build/firmware.elf: $(FW_SOURCES) $(FW_LINKER) Makefile | build
	$(RISCV_PREFIX)gcc $(FW_FLAGS) -T $(FW_LINKER) $(FW_SOURCES) -o $@

build/firmware.hex: build/firmware.elf
	$(RISCV_PREFIX)objcopy -O verilog $< $@

build/rom.v: build/firmware.hex $(HEX2ROM)
	$(PYTHON) $(HEX2ROM) $< $@

build/tb_soc.vvp: build/rom.v $(RTL_SOURCES) $(TB_SOURCES) Makefile
	$(IVERILOG) -g2012 -s tb_soc -o $@ $(TB_SOURCES) $(RTL_SOURCES) build/rom.v

clean:
	rm -f build/firmware.elf build/firmware.hex build/rom.v build/tb_soc.vvp build/soc.vcd
