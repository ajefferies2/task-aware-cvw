SHELL := /bin/bash
ROOT := $(abspath ../..)
HERE := $(abspath .)
JOBS ?= 4
TASKS ?= 2
override TASKS := $(shell python3 build_config.py --tasks '$(TASKS)' --field tasks)
ifeq ($(strip $(TASKS)),)
$(error Invalid TASKS: specify an integer from 1 through 255)
endif
override RAM_BYTES := $(shell python3 build_config.py --tasks '$(TASKS)' --field ram_bytes)
override CONTEXTS := $(shell python3 build_config.py --tasks '$(TASKS)' --field contexts)
# Direction predictor: twobit (bimodal, task banks) or gshare (per-task history).
PREDICTOR ?= twobit
PREDICTOR_CODE := $(or $(if $(filter twobit,$(PREDICTOR)),8),$(if $(filter gshare,$(PREDICTOR)),9))
ifeq ($(PREDICTOR_CODE),)
$(error Invalid PREDICTOR: use twobit or gshare)
endif
VERILATOR ?= verilator
CROSS_COMPILE ?= /opt/zephyr-sdk/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-
RTL := $(ROOT)/src/cvw.sv $(filter-out $(ROOT)/src/cvw.sv,$(shell find $(ROOT)/src -name '*.sv' | sort))
BUILD := build/$(PREDICTOR)-tasks-$(TASKS)
SW_BUILD := sw/build/tasks-$(TASKS)
SIM := $(BUILD)/obj_dir/Vtask_bpred_tb

.PHONY: all sim software run test
all: sim software
sim: $(SIM)

$(SIM): Makefile build_config.py task_bpred_tb.sv dpi.cpp config/config.vh $(RTL) $(wildcard $(ROOT)/config/shared/*.vh)
	mkdir -p $(BUILD)
	@$(VERILATOR) --binary --timing --assert --trace -Wno-fatal -j $(JOBS) \
	  --top-module task_bpred_tb --Mdir $(HERE)/$(BUILD)/obj_dir \
	  -DBPRED_TASKS=$(CONTEXTS) -DTASK_BPRED_RAM_BYTES=$(RAM_BYTES) \
	  -DTASK_BPRED_TYPE=$(PREDICTOR_CODE) \
	  -I$(HERE)/config -I$(ROOT)/config/shared \
	  $(RTL) $(HERE)/task_bpred_tb.sv $(HERE)/dpi.cpp > $(BUILD)/compile.log 2>&1 || { tail -n 80 $(BUILD)/compile.log; exit 1; }

software:
	$(MAKE) -C sw TASKS=$(TASKS) RAM_BYTES=$(RAM_BYTES) CROSS_COMPILE=$(CROSS_COMPILE)
	python3 bin_to_mem.py --ram-bytes $(RAM_BYTES) $(SW_BUILD)/workloads.bin $(SW_BUILD)/workloads.mem

run: all
	python3 run_experiments.py --tasks $(TASKS) --predictor $(PREDICTOR) --workloads 0 --quanta 16 --iterations 1024 --no-plot --output $(BUILD)/smoke_results

test: all
	TASKS=$(TASKS) bash tests/run_predictor_tests.sh
	python3 run_experiments.py --tasks $(TASKS) --predictor $(PREDICTOR) --quanta 1 16 --iterations 64 --embench-quanta 500 --embench-reps 4 --no-plot --output $(BUILD)/test_results
