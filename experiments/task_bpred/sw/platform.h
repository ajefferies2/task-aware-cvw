#ifndef TASK_BPRED_PLATFORM_H
#define TASK_BPRED_PLATFORM_H

typedef unsigned int u32;
typedef unsigned long uptr;

/* The testbench initializes args before reset is released. */
#define REG32(addr) (*(volatile u32 *)(uptr)(addr))
#define ARG_MODE       REG32(0x8000ffe0u)
#define ARG_QUANTUM    REG32(0x8000ffe4u)
#define ARG_WORKLOAD   REG32(0x8000ffe8u)
#define ARG_ITERATIONS REG32(0x8000ffecu)
#define STATUS        REG32(0x8000fff0u)
#define MEASURE       REG32(0x8000fff4u)
#define CHECKSUM      REG32(0x8000fff8u)
#define RESULT(n)     REG32(0x8000ffb0u + 4u * (n))

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
