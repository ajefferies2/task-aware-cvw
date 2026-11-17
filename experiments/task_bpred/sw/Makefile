SHELL := /bin/bash
TASKS ?= 2
override TASKS := $(shell python3 ../build_config.py --tasks '$(TASKS)' --field tasks)
ifeq ($(strip $(TASKS)),)
$(error Invalid TASKS: specify an integer from 1 through 255)
endif
override RAM_BYTES := $(shell python3 ../build_config.py --tasks '$(TASKS)' --field ram_bytes)
BUILD := build/tasks-$(TASKS)
CROSS_COMPILE ?= /opt/zephyr-sdk/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
NM := $(CROSS_COMPILE)nm
CFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32 -O2 -g \
          -ffreestanding -nostdlib -fno-builtin -fno-pic -fno-stack-protector \
          -msmall-data-limit=0 -mno-relax -Wall -Wextra -Werror
CPPFLAGS := -DTASK_COUNT=$(TASKS) -DRAM_BYTES=$(RAM_BYTES)
SOURCES := start.S context.S hot.S smoke.S workload.c preempt.S preempt.c minilibc.c

# Embench-IoT kernels for the preemptive workload, one per task, in task-ID
# order. Each kernel is wrapped so its static benchmark_body() can run one
# repetition at a time, then every symbol except its three entry points is made
# local so kernels cannot clash.
EMBENCH := $(abspath ../../../addins/embench-iot)
KERNELS := crc32 statemate nsichneu
SRC_crc32 := crc32/crc_32.c
SRC_statemate := statemate/libstatemate.c
SRC_nsichneu := nsichneu/libnsichneu.c
EMBENCH_CFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32 -O2 -g -ffreestanding -fno-builtin \
                  -fno-pic -fno-stack-protector -msmall-data-limit=0 -mno-relax -w \
                  -I$(EMBENCH)/support -DCPU_MHZ=1 -DWARMUP_HEAT=0
EMBENCH_OBJS := $(KERNELS:%=$(BUILD)/embench_%.o) $(BUILD)/beebsc.o
.SECONDARY: $(KERNELS:%=$(BUILD)/embench_%.c)

.PHONY: all clean FORCE
all: $(BUILD)/workloads.bin $(BUILD)/workloads.nm $(BUILD)/workloads.dump

$(BUILD):
	mkdir -p $@

$(BUILD)/config.args: FORCE | $(BUILD)
	@printf '%s\n' '$(CPPFLAGS) $(CROSS_COMPILE)' > $@.tmp
	@cmp -s $@.tmp $@ || cp $@.tmp $@

$(BUILD)/link.ld: link.ld config.h $(BUILD)/config.args Makefile
	$(CC) $(CPPFLAGS) -E -P -x c link.ld -o $@

$(BUILD)/embench_%.c: Makefile | $(BUILD)
	printf '#include "%s"\nint embench_$*_run(int rpt) { return benchmark_body(rpt); }\n' \
	  '$(EMBENCH)/src/$(SRC_$*)' > $@

$(BUILD)/embench_%.o: $(BUILD)/embench_%.c
	$(CC) $(EMBENCH_CFLAGS) -Dinitialise_benchmark=embench_$*_init -Dverify_benchmark=embench_$*_verify \
	  -Dbenchmark=embench_$*_benchmark -Dwarm_caches=embench_$*_warm -c $< -o $@
	$(OBJCOPY) -G embench_$*_init -G embench_$*_run -G embench_$*_verify $@

$(BUILD)/beebsc.o: $(EMBENCH)/support/beebsc.c Makefile | $(BUILD)
	$(CC) $(EMBENCH_CFLAGS) -DNDEBUG -c $< -o $@

$(BUILD)/workloads.elf: $(SOURCES) $(EMBENCH_OBJS) platform.h config.h $(BUILD)/link.ld $(BUILD)/config.args Makefile
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wl,-T,$(BUILD)/link.ld,-Map,$(BUILD)/workloads.map $(SOURCES) $(EMBENCH_OBJS) -o $@

$(BUILD)/workloads.bin: $(BUILD)/workloads.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/workloads.nm: $(BUILD)/workloads.elf
	$(NM) -n $< > $@

$(BUILD)/workloads.dump: $(BUILD)/workloads.elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -rf build
