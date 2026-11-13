#include "platform.h"

extern void context_switch(u32 **old_sp, u32 *new_sp);
extern u32 hot_shared(u32 condition, u32 sum);
extern unsigned char hot_task_base[];
extern unsigned char hot_task_stride[];

struct task {
  u32 *sp;
  u32 checksum;
  u32 completed;
  u32 done;
};
static struct task tasks[TASK_COUNT];
static u32 stacks[TASK_COUNT][1024] __attribute__((aligned(16)));
static u32 *scheduler_sp;
static volatile u32 active_task;
static u32 mode, quantum, workload, iterations;

static u32 random_next(u32 x) {
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  return x;
}

static void task_entry(void) {
  const u32 id = active_task;
  struct task *const task = &tasks[id];
  u32 random = 0x13579bdfu ^ (id * 0x9e3779b9u);
  u32 sum = 0;
  u32 i = 0;
  u32 (*hot)(u32, u32) = hot_shared;
  if (workload == 3)
    hot = (u32 (*)(u32, u32))(uptr)((uptr)hot_task_base + id * (uptr)hot_task_stride);
  for (;;) {
    /* Checks preserved locals, correct stack, and CSR identity after resume. */
    if (get_context() != ((mode << 8) | id)) fail(0x20u + id);
    u32 end = i + quantum;
    if (end > iterations) end = iterations;
    while (i < end) {
      u32 condition = id & 1u;
      if (workload == 1) condition = ((i >> 3) & 1u) ^ (id & 1u);
      if (workload == 2) {
        random = random_next(random);
        condition = random & 1u;
      }
      sum = hot(condition, sum);
      ++i;
    }
    task->checksum = sum;
    task->completed = i;
    task->done = (i == iterations);
    context_switch(&task->sp, scheduler_sp);
  }
}

static u32 expected(u32 id) {
  u32 sum = 0;
  u32 random = 0x13579bdfu ^ (id * 0x9e3779b9u);
  for (u32 i = 0; i < iterations; ++i) {
    u32 condition = id & 1u;
    if (workload == 1) condition = ((i >> 3) & 1u) ^ (id & 1u);
    if (workload == 2) {
      random = random_next(random);
      condition = random & 1u;
    }
    sum += 7u - 4u * condition;
  }
  return sum;
}

int main(void) {
  RESULT(3) = TASK_COUNT;
  u32 check = isa_smoke();
  if (check) fail(check);
  mode = ARG_MODE;
  quantum = ARG_QUANTUM;
  workload = ARG_WORKLOAD;
  iterations = ARG_ITERATIONS;
  if (mode > 1 || quantum == 0 || quantum > 1048576u ||
      workload > 3 || iterations == 0 || iterations > 1048576u)
    fail(0x10);
  for (u32 id = 0; id < TASK_COUNT; ++id) {
    u32 *frame = &stacks[id][1024 - 16];
    frame[0] = (u32)(uptr)task_entry;
    tasks[id].sp = frame;
  }
  u32 switches = 0;
  set_context(mode << 8);
  u32 start_cycle = cycle();
  u32 start_instret = instret();
  MEASURE = 1;
  u32 finished = 0;
  while (finished != TASK_COUNT) {
    for (u32 id = 0; id < TASK_COUNT; ++id) {
      if (!tasks[id].done) {
        active_task = id;
        set_context((mode << 8) | id);
        ++switches;
        context_switch(&scheduler_sp, tasks[id].sp);
        finished += tasks[id].done;
      }
    }
  }
  MEASURE = 0;
  u32 elapsed = cycle() - start_cycle;
  u32 retired = instret() - start_instret;
  RESULT(0) = elapsed;
  RESULT(1) = retired;
  RESULT(2) = switches;
  u32 aggregate = 2166136261u;
  for (u32 id = 0; id < TASK_COUNT; ++id) {
    u32 correct = expected(id);
    TASK_RESULT(id, 0) = tasks[id].checksum;
    TASK_RESULT(id, 1) = correct;
    TASK_RESULT(id, 2) = tasks[id].completed;
    if (tasks[id].checksum != correct || tasks[id].completed != iterations)
      fail(0x1000u + id);
    aggregate = (aggregate ^ tasks[id].checksum) * 16777619u;
  }
  CHECKSUM = aggregate;
  STATUS = 1;
  for (;;) __asm__ volatile ("nop");
}
