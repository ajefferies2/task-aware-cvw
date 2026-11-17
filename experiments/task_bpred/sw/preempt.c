/* Preemptive round-robin scheduler running one Embench-IoT kernel per task.
 *
 * The testbench raises the machine timer interrupt after a set number of
 * cycles spent in task code, like an RTOS tick. preempt_entry (preempt.S)
 * saves the task's registers; preempt_schedule() runs under the scheduler's
 * own predictor context, picks the next unfinished task, and switches the
 * context ID to it just before returning. A finished task issues ecall and is
 * never scheduled again. main starts the run with ecall and resumes when every
 * task has finished. */
#include "platform.h"

typedef struct {
  void (*init)(void);
  int (*run)(int repetitions);
  int (*verify)(int result);
} kernel_t;

#define KERNEL(name) \
  extern void embench_##name##_init(void); \
  extern int embench_##name##_run(int); \
  extern int embench_##name##_verify(int);
/* A regular loop, a state machine, and very branchy control code. */
KERNEL(crc32) KERNEL(statemate) KERNEL(nsichneu)
#define ENTRY(name) {embench_##name##_init, embench_##name##_run, embench_##name##_verify}
/* Order must match KERNELS in the Makefile; task i runs kernels[i]. */
static const kernel_t kernels[] = {ENTRY(crc32), ENTRY(statemate), ENTRY(nsichneu)};
#define KERNEL_COUNT (sizeof kernels / sizeof kernels[0])

#define MAIN TASK_COUNT          /* "current" value while main is running */
#define CAUSE_ECALL 11u
#define CAUSE_TIMER 0x80000007u
#define MSTATUS_MPIE 0x80u
#define MIE_MTIE 0x80u

extern void preempt_entry(void);
static u32 stacks[TASK_COUNT][1024] __attribute__((aligned(16)));
static u32 *frames[TASK_COUNT], *main_frame;
static u32 passed[TASK_COUNT], completed[TASK_COUNT], done[TASK_COUNT];
static volatile u32 current;
static u32 mode_bits, repetitions, dispatches;

/* Each task runs its kernel one repetition at a time and verifies every result. */
static void task_body(void) {
  const u32 id = current;
  const kernel_t *k = &kernels[id];
  k->init();
  u32 ok = 0;
  for (u32 i = 0; i < repetitions; ++i)
    ok += k->verify(k->run(1)) ? 1u : 0u;
  passed[id] = ok;
  completed[id] = repetitions;
  for (;;) __asm__ volatile ("ecall");
}

u32 *preempt_schedule(u32 *frame, u32 cause) {
  set_context(mode_bits | KERNEL_ID);
  if (cause == CAUSE_ECALL) {          /* main starting, or a task finished */
    frame[0] += 4;
    if (current == MAIN) main_frame = frame;
    else done[current] = 1;
  } else if (cause == CAUSE_TIMER && current != MAIN) {
    frames[current] = frame;
  } else {
    fail(0x2000u | (cause & 0xffu));
  }
  /* Round robin over unfinished tasks, starting after the current one. */
  u32 next = MAIN;
  for (u32 n = 0; n < TASK_COUNT; ++n) {
    u32 id = (current == MAIN) ? n : (current + 1 + n) % TASK_COUNT;
    if (!done[id]) { next = id; break; }
  }
  current = next;
  if (next == MAIN) {                  /* all done: return to main, interrupts off */
    __asm__ volatile ("csrc mstatus, %0" : : "r"(MSTATUS_MPIE));
    return main_frame;
  }
  ++dispatches;
  __asm__ volatile ("csrs mstatus, %0" : : "r"(MSTATUS_MPIE));
  set_context(mode_bits | next);
  return frames[next];
}

void run_preemptive(u32 mode, u32 reps) {
  if (TASK_COUNT > KERNEL_COUNT) fail(0x11);  /* kernels have static state */
  mode_bits = mode << 8;
  repetitions = reps;
  u32 gp;
  __asm__ volatile ("mv %0, gp" : "=r"(gp));
  for (u32 id = 0; id < TASK_COUNT; ++id) {
    u32 *f = &stacks[id][1024 - 32];
    for (u32 i = 0; i < 32; ++i) f[i] = 0;
    f[0] = (u32)(uptr)task_body;           /* mepc */
    f[2] = (u32)(uptr)&stacks[id][1024];   /* sp */
    f[3] = gp;
    frames[id] = f;
  }
  current = MAIN;
  __asm__ volatile ("csrw mtvec, %0" : : "r"(preempt_entry));
  __asm__ volatile ("csrs mie, %0" : : "r"(MIE_MTIE));
  set_context(mode_bits | KERNEL_ID);
  u32 start_cycle = cycle();
  u32 start_instret = instret();
  MEASURE = 1;
  __asm__ volatile ("ecall" : : : "memory");
  MEASURE = 0;
  RESULT(0) = cycle() - start_cycle;
  RESULT(1) = instret() - start_instret;
  RESULT(2) = dispatches;
  u32 aggregate = 2166136261u;
  for (u32 id = 0; id < TASK_COUNT; ++id) {
    TASK_RESULT(id, 0) = passed[id];
    TASK_RESULT(id, 1) = reps;              /* every repetition must verify */
    TASK_RESULT(id, 2) = completed[id];
    if (passed[id] != reps || completed[id] != reps) fail(0x1000u + id);
    aggregate = (aggregate ^ passed[id]) * 16777619u;
  }
  CHECKSUM = aggregate;
}
