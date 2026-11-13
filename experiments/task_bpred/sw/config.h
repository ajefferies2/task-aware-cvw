#ifndef TASK_BPRED_CONFIG_H
#define TASK_BPRED_CONFIG_H

#ifndef TASK_COUNT
#define TASK_COUNT 2
#endif
#ifndef RAM_BYTES
#define RAM_BYTES 65536
#endif
#if TASK_COUNT < 1 || TASK_COUNT > 256
#error "TASK_COUNT must be in 1..256"
#endif
#if RAM_BYTES < 65536 || (RAM_BYTES & (RAM_BYTES - 1))
#error "RAM_BYTES must be a power of two >= 65536"
#endif
#if RAM_BYTES < (4096 * TASK_COUNT + 32768)
#error "RAM_BYTES must reserve room for task stacks, code, scheduler and mailbox"
#endif

#define RAM_END (0x80000000 + RAM_BYTES)
#define RESULTS_BASE (RAM_END - 4096)
#define STATUS_ADDR (RAM_END - 16)

#endif
