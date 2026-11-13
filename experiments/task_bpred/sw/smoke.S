/* Return 0 on success. Distinct failure codes identify architectural checks. */
.section .text,"ax",@progbits
.option norvc
.globl isa_smoke
isa_smoke:
  addi sp, sp, -32
  sw ra, 28(sp)
  li a0, 0x40
  li t0, 0x12345678
  sw t0, 0(sp)
  lw t1, 0(sp)
  bne t0, t1, 9f
  li a0, 0x41
  li t0, -128
  sb t0, 4(sp)
  lb t1, 4(sp)
  bne t0, t1, 9f
  lbu t1, 4(sp)
  li t0, 128
  bne t0, t1, 9f
  li a0, 0x42
  li t0, 0x8001
  sh t0, 6(sp)
  lhu t1, 6(sp)
  bne t0, t1, 9f
  lh t1, 6(sp)
  li t0, -32767
  bne t0, t1, 9f
  li a0, 0x43
  li t0, -7
  li t1, 6
  mul t2, t0, t1
  li t3, -42
  bne t2, t3, 9f
  div t2, t3, t1
  bne t2, t0, 9f
  rem t2, t3, t1
  bnez t2, 9f
  li a0, 0x44
  srai t2, t0, 2
  li t3, -2
  bne t2, t3, 9f
  srli t2, t0, 31
  li t3, 1
  bne t2, t3, 9f
  blt t0, t1, 1f
  j 9f
1:
  bltu t0, t1, 9f
  li t2, 7
2:
  addi t2, t2, -1
  bnez t2, 2b
  li a0, 0x45
  call 3f
  j 4f
3:
  li t2, 0x5a5
  ret
4:
  li t3, 0x5a5
  bne t2, t3, 9f
  /* Adjacent CSR accesses and the first conditional branch after each write. */
  li a0, 0x46
  li t0, 0x101
  csrw 0xbc0, t0
  csrr t1, 0xbc0
  bne t0, t1, 9f
  li t0, 0x100
  csrw 0xbc0, t0
  csrr t1, 0xbc0
  bne t0, t1, 9f
  li t0, 1
  csrw 0xbc0, t0
  csrr t1, 0xbc0
  bne t0, t1, 9f
  csrw 0xbc0, zero
  csrr t1, 0xbc0
  bnez t1, 9f
  li t0, -1
  csrw 0xbc0, t0
  csrr t1, 0xbc0
  li t0, 0x101
  bne t0, t1, 9f
  csrw 0xbc0, zero
  li a0, 0x47
  csrr t0, mcycle
  nop
  nop
  csrr t1, mcycle
  bgeu t0, t1, 9f
  li a0, 0
9:
  lw ra, 28(sp)
  addi sp, sp, 32
  ret
