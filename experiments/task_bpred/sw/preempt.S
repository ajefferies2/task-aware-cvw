/* Trap entry for the preemptive workload. Saves the interrupted context as a
 * 32-word frame on its own stack (word 0 = mepc, word i = register x_i), lets
 * preempt_schedule() pick the next context, then restores that frame.
 * No branches run between the scheduler's context-ID write and mret. */
.section .text,"ax",@progbits
.option norvc
.balign 4
.globl preempt_entry
preempt_entry:
  addi sp, sp, -128
  sw x1, 4(sp)
  sw x3, 12(sp)
  sw x4, 16(sp)
  sw x5, 20(sp)
  sw x6, 24(sp)
  sw x7, 28(sp)
  sw x8, 32(sp)
  sw x9, 36(sp)
  sw x10, 40(sp)
  sw x11, 44(sp)
  sw x12, 48(sp)
  sw x13, 52(sp)
  sw x14, 56(sp)
  sw x15, 60(sp)
  sw x16, 64(sp)
  sw x17, 68(sp)
  sw x18, 72(sp)
  sw x19, 76(sp)
  sw x20, 80(sp)
  sw x21, 84(sp)
  sw x22, 88(sp)
  sw x23, 92(sp)
  sw x24, 96(sp)
  sw x25, 100(sp)
  sw x26, 104(sp)
  sw x27, 108(sp)
  sw x28, 112(sp)
  sw x29, 116(sp)
  sw x30, 120(sp)
  sw x31, 124(sp)
  addi t0, sp, 128      /* interrupted sp */
  sw t0, 8(sp)
  csrr t0, mepc
  sw t0, 0(sp)
  mv a0, sp
  csrr a1, mcause
  call preempt_schedule /* returns the frame to resume */
  mv sp, a0
  lw t0, 0(sp)
  csrw mepc, t0
  lw x1, 4(sp)
  lw x3, 12(sp)
  lw x4, 16(sp)
  lw x5, 20(sp)
  lw x6, 24(sp)
  lw x7, 28(sp)
  lw x8, 32(sp)
  lw x9, 36(sp)
  lw x10, 40(sp)
  lw x11, 44(sp)
  lw x12, 48(sp)
  lw x13, 52(sp)
  lw x14, 56(sp)
  lw x15, 60(sp)
  lw x16, 64(sp)
  lw x17, 68(sp)
  lw x18, 72(sp)
  lw x19, 76(sp)
  lw x20, 80(sp)
  lw x21, 84(sp)
  lw x22, 88(sp)
  lw x23, 92(sp)
  lw x24, 96(sp)
  lw x25, 100(sp)
  lw x26, 104(sp)
  lw x27, 108(sp)
  lw x28, 112(sp)
  lw x29, 116(sp)
  lw x30, 120(sp)
  lw x31, 124(sp)
  lw x2, 8(sp)
  mret
