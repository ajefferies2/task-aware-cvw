# Run the experiment

```sh
make TASKS=8 test
python3 run_experiments.py --tasks 8
```

Run from this directory. The default compiler is the local Zephyr SDK; override
with `make CROSS_COMPILE=riscv64-unknown-elf-`. Use `--no-plot` without Matplotlib.
`TASKS` defaults to 2 and accepts 1–256. Hardware and software must use the same
count; each count has its own build directory. RAM grows to fit the task stacks.

Print actual counter updates from the RTL unit test:

```sh
bash tests/run_predictor_tests.sh +show_counters
```

Counters start at `01`. Taken branches increment toward `11`; not-taken branches
decrement toward `00`. They stop at those limits. The upper bit is the prediction.

| Mode | Index, with compressed instructions disabled |
|---|---|
| Shared | `PC[9:2]` |
| Task-aware, 2 tasks | `{task_id[0], PC[8:2]}` |
| Task-aware, 8 tasks | `{task_id[2:0], PC[6:2]}` |

The table always has 256 counters. Task banks round up to a power of two; three
tasks reserve four 64-counter banks, with one unused.

The scheduler writes CSR `0xBC0`: bits 7:0 are task ID, bit 8 enables partitioning.
Valid IDs are `0` through `TASKS-1`; an out-of-range ID writes back as zero.
The lookup index travels with the branch so a later switch cannot change its
update destination.

- [Predictor RTL](../../src/ifu/bpred/taskTwoBitPredictor.sv)
- [Scheduler](sw/workload.c) and [context switch](sw/context.S)
- [Counter trace](results/counter_trace.txt), [results](results/report.md), and [plots](results/comparison.png)
- [Memory map, measurement definitions, and limitations](DESIGN.md)
