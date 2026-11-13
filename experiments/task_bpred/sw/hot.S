/* These explicit branches cannot be optimized into arithmetic by the compiler.
 * Both outcomes execute an add and a return. Symbol ranges contain only the
 * conditional branch, for hot-site-only statistics in the testbench. */
#include "config.h"
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
.globl hot_task_base, hot_task_stride, compiled_task_count
.set hot_task_stride, 20
.set compiled_task_count, TASK_COUNT
hot_task_base:
.rept TASK_COUNT
  beqz a0, 2f
  addi a0, a1, 3
  ret
2:
  addi a0, a1, 7
  ret
.endr
