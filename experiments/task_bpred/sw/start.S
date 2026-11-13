/* Minimal machine-mode startup. No libc, operating system, or interrupts. */
.section .text.start,"ax",@progbits
.option norvc
.globl _start
_start:
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop
  la sp, __stack_top
  csrw mstatus, zero
  la t0, trap_handler
  csrw mtvec, t0
  la t0, __bss_start
  la t1, __bss_end
1:
  bgeu t0, t1, 2f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 1b
2:
  call main
  /* A returning main is an error; success writes the status itself. */
  li t0, 0x8000fff0
  li t1, 0x7fffffff
  sw t1, 0(t0)
3:
  j 3b

.balign 4
.globl trap_handler
trap_handler:
  li t0, 0x8000ffb0
  csrr t1, mcause
  sw t1, 20(t0)
  csrr t2, mepc
  sw t2, 24(t0)
  csrr t2, mtval
  sw t2, 28(t0)
  li t0, 0x8000fff0
  sw zero, 4(t0)
  li t2, 0x80000000
  or t1, t1, t2
  sw t1, 0(t0)
4:
  j 4b
