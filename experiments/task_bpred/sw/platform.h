#ifndef TASK_BPRED_PLATFORM_H
#define TASK_BPRED_PLATFORM_H
#include "config.h"

typedef unsigned int u32;
typedef unsigned long uptr;

/* The testbench initializes args before reset is released. */
#define REG32(addr) (*(volatile u32 *)(uptr)(addr))
#define ARG_MODE       REG32(RAM_END - 32u)
#define ARG_QUANTUM    REG32(RAM_END - 28u)
#define ARG_WORKLOAD   REG32(RAM_END - 24u)
#define ARG_ITERATIONS REG32(RAM_END - 20u)
#define STATUS        REG32(STATUS_ADDR)
#define MEASURE       REG32(RAM_END - 12u)
#define CHECKSUM      REG32(RAM_END - 8u)
#define RESULT(n)     REG32(RESULTS_BASE + 4u * (n))
#define TASK_RESULT(id, field) REG32(RESULTS_BASE + 32u + 12u * (id) + 4u * (field))

static inline void set_context(u32 value) {
  __asm__ volatile ("csrw 0xbc0, %0" : : "r"(value) : "memory");
}
static inline u32 get_context(void) {
  u32 value;
  __asm__ volatile ("csrr %0, 0xbc0" : "=r"(value));
  return value;
}
static inline u32 cycle(void) {
  u32 value;
  __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
  return value;
}
static inline u32 instret(void) {
  u32 value;
  __asm__ volatile ("csrr %0, minstret" : "=r"(value));
  return value;
}
static inline void fail(u32 code) {
  MEASURE = 0;
  STATUS = code;
  for (;;) __asm__ volatile ("nop");
}
u32 isa_smoke(void);

#endif
