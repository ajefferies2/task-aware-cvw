#include "platform.h"

extern void context_switch(u32 **old_sp, u32 *new_sp);
extern u32 hot_shared(u32 condition, u32 sum);
extern u32 hot_task0(u32 condition, u32 sum);
extern u32 hot_task1(u32 condition, u32 sum);

struct task {
  u32 *sp;
  u32 checksum;
  u32 completed;
  u32 done;
};
static struct task tasks[2];
static u32 stacks[2][1024] __attribute__((aligned(16)));
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
  if (workload == 3) hot = id ? hot_task1 : hot_task0;
  for (;;) {
    /* Checks preserved locals, correct stack, and CSR identity after resume. */
    if (get_context() != ((mode << 8) | id)) fail(0x20u + id);
    u32 end = i + quantum;
    if (end > iterations) end = iterations;
    while (i < end) {
      u32 condition = id;
      if (workload == 1) condition = ((i >> 3) & 1u) ^ id;
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
    u32 condition = id;
    if (workload == 1) condition = ((i >> 3) & 1u) ^ id;
    if (workload == 2) {
      random = random_next(random);
      condition = random & 1u;
    }
    sum += 7u - 4u * condition;
  }
  return sum;
}

int main(void) {
  u32 check = isa_smoke();
  if (check) fail(check);
  mode = ARG_MODE;
  quantum = ARG_QUANTUM;
  workload = ARG_WORKLOAD;
  iterations = ARG_ITERATIONS;
  if (mode > 1 || quantum == 0 || quantum > 1048576u ||
      workload > 3 || iterations == 0 || iterations > 1048576u)
    fail(0x10);
  for (u32 id = 0; id < 2; ++id) {
    u32 *frame = &stacks[id][1024 - 16];
    frame[0] = (u32)(uptr)task_entry;
    tasks[id].sp = frame;
  }
  u32 switches = 0;
  set_context(mode << 8);
  u32 start_cycle = cycle();
  u32 start_instret = instret();
  MEASURE = 1;
  while (!(tasks[0].done && tasks[1].done)) {
    for (u32 id = 0; id < 2; ++id) {
      if (!tasks[id].done) {
        active_task = id;
        set_context((mode << 8) | id);
        ++switches;
        context_switch(&scheduler_sp, tasks[id].sp);
      }
    }
  }
  MEASURE = 0;
  u32 elapsed = cycle() - start_cycle;
  u32 retired = instret() - start_instret;
  RESULT(0) = tasks[0].checksum;
  RESULT(1) = tasks[1].checksum;
  RESULT(2) = elapsed;
  RESULT(3) = retired;
  RESULT(4) = switches;
  RESULT(8) = expected(0);
  RESULT(9) = expected(1);
  RESULT(10) = tasks[0].completed;
  RESULT(11) = tasks[1].completed;
  if (tasks[0].checksum != RESULT(8) || tasks[1].checksum != RESULT(9) ||
      tasks[0].completed != iterations || tasks[1].completed != iterations)
    fail(0x30);
  CHECKSUM = tasks[0].checksum ^ (tasks[1].checksum << 16) ^
             (tasks[1].checksum >> 16);
  STATUS = 1;
  for (;;) __asm__ volatile ("nop");
}
