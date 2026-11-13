# Run the experiment

```sh
make test
python3 run_experiments.py
```

Run from this directory. The default compiler is the local Zephyr SDK; override
with `make CROSS_COMPILE=riscv64-unknown-elf-`. Use `--no-plot` without Matplotlib.

Print actual counter updates from the RTL unit test:

```sh
bash tests/run_predictor_tests.sh +show_counters
```

Counters start at `01`. Taken branches increment toward `11`; not-taken branches
decrement toward `00`. They stop at those limits. The upper bit is the prediction.

| Mode | Index, with compressed instructions disabled |
|---|---|
| Shared | `PC[9:2]` |
| Task-aware | `{task_id, PC[8:2]}` |

The scheduler writes CSR `0xBC0`: bit 0 is task ID, bit 8 enables partitioning.
The lookup index travels with the branch so a later switch cannot change its
update destination.

- [Predictor RTL](../../src/ifu/bpred/taskTwoBitPredictor.sv)
- [Scheduler](sw/workload.c) and [context switch](sw/context.S)
- [Counter trace](results/counter_trace.txt), [results](results/report.md), and [plots](results/comparison.png)
- [Memory map, measurement definitions, and limitations](DESIGN.md)
