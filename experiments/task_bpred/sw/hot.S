/* These explicit branches cannot be optimized into arithmetic by the compiler.
 * Both outcomes execute an add and a return. Symbol ranges contain only the
 * conditional branch, for hot-site-only statistics in the testbench. */
.section .text.hot,"ax",@progbits
.option norvc
.balign 64
.globl hot_shared, hot_start, hot_end
hot_shared:
hot_start:
  beqz a0, 1f
hot_end:
  addi a0, a1, 3
  ret
1:
  addi a0, a1, 7
  ret

.balign 64
.globl hot_task0, task0_hot_start, task0_hot_end
hot_task0:
task0_hot_start:
  beqz a0, 2f
task0_hot_end:
  addi a0, a1, 3
  ret
2:
  addi a0, a1, 7
  ret

.balign 64
.globl hot_task1, task1_hot_start, task1_hot_end
hot_task1:
task1_hot_start:
  beqz a0, 3f
task1_hot_end:
  addi a0, a1, 3
  ret
3:
  addi a0, a1, 7
  ret
