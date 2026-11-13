SHELL := /bin/bash
ROOT := $(abspath ../..)
HERE := $(abspath .)
JOBS ?= 4
VERILATOR ?= verilator
CROSS_COMPILE ?= /opt/zephyr-sdk/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-
RTL := $(ROOT)/src/cvw.sv $(filter-out $(ROOT)/src/cvw.sv,$(shell rg --files $(ROOT)/src -g '*.sv' | sort))
SIM := build/obj_dir/Vtask_bpred_tb

.PHONY: all sim software run test
all: sim software
sim: $(SIM)

$(SIM): Makefile task_bpred_tb.sv dpi.cpp config/config.vh $(RTL) $(wildcard $(ROOT)/config/shared/*.vh)
	mkdir -p build
	@$(VERILATOR) --binary --timing --assert --trace -Wno-fatal -j $(JOBS) \
	  --top-module task_bpred_tb --Mdir $(HERE)/build/obj_dir \
	  -I$(HERE)/config -I$(ROOT)/config/shared \
	  $(RTL) $(HERE)/task_bpred_tb.sv $(HERE)/dpi.cpp > build/compile.log 2>&1 || { tail -n 80 build/compile.log; exit 1; }

software:
	$(MAKE) -C sw CROSS_COMPILE=$(CROSS_COMPILE)
	python3 bin_to_mem.py sw/build/workloads.bin sw/build/workloads.mem

run: all
	python3 run_experiments.py --workloads 0 --quanta 16 --iterations 1024 --no-plot --output build/smoke_results

test: all
	bash tests/run_predictor_tests.sh
	python3 run_experiments.py --quanta 1 16 --iterations 64 --no-plot --output build/test_results
