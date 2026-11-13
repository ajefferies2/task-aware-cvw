SHELL := /bin/bash
CROSS_COMPILE ?= /opt/zephyr-sdk/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
NM := $(CROSS_COMPILE)nm
CFLAGS := -march=rv32im_zicsr_zifencei -mabi=ilp32 -O2 -g \
          -ffreestanding -nostdlib -fno-builtin -fno-pic -fno-stack-protector \
          -msmall-data-limit=0 -mno-relax -Wall -Wextra -Werror
SOURCES := start.S context.S hot.S smoke.S workload.c

.PHONY: all clean
all: build/workloads.bin build/workloads.nm build/workloads.dump

build:
	mkdir -p $@

build/workloads.elf: $(SOURCES) platform.h link.ld Makefile | build
	$(CC) $(CFLAGS) -Wl,-T,link.ld,-Map,build/workloads.map $(SOURCES) -o $@

build/workloads.bin: build/workloads.elf
	$(OBJCOPY) -O binary $< $@

build/workloads.nm: build/workloads.elf
	$(NM) -n $< > $@

build/workloads.dump: build/workloads.elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -rf build
