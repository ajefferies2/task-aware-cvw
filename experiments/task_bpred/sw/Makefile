SHELL := /bin/bash
TASKS ?= 2
override TASKS := $(shell python3 ../build_config.py --tasks '$(TASKS)' --field tasks)
ifeq ($(strip $(TASKS)),)
$(error Invalid TASKS: specify an integer from 1 through 256)
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
SOURCES := start.S context.S hot.S smoke.S workload.c

.PHONY: all clean FORCE
all: $(BUILD)/workloads.bin $(BUILD)/workloads.nm $(BUILD)/workloads.dump

$(BUILD):
	mkdir -p $@

$(BUILD)/config.args: FORCE | $(BUILD)
	@printf '%s\n' '$(CPPFLAGS) $(CROSS_COMPILE)' > $@.tmp
	@cmp -s $@.tmp $@ || cp $@.tmp $@

$(BUILD)/link.ld: link.ld config.h $(BUILD)/config.args Makefile
	$(CC) $(CPPFLAGS) -E -P -x c link.ld -o $@

$(BUILD)/workloads.elf: $(SOURCES) platform.h config.h $(BUILD)/link.ld $(BUILD)/config.args Makefile
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wl,-T,$(BUILD)/link.ld,-Map,$(BUILD)/workloads.map $(SOURCES) -o $@

$(BUILD)/workloads.bin: $(BUILD)/workloads.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/workloads.nm: $(BUILD)/workloads.elf
	$(NM) -n $< > $@

$(BUILD)/workloads.dump: $(BUILD)/workloads.elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -rf build
