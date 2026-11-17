# Run the experiment

```sh
git submodule update --init addins/embench-iot   # once, from the repository root
./sweep.sh                                       # the study, into results/<config>/
```

Run from this directory. The compiler is Zephyr SDK 0.17.4; point `CROSS_COMPILE`
at it if it is not in `/opt/zephyr-sdk`. `sweep.sh` builds 3 tasks with each
predictor (`PREDICTOR=twobit` or `gshare`) and runs three workloads in both modes:
the shared-branch workload, its control, and real Embench kernels preempted by a
timer interrupt. The scheduler has its own predictor context, so the hardware has
`TASKS + 1` contexts. `make TASKS=3 PREDICTOR=gshare test` runs the unit tests and
a short matrix.

Print actual counter updates from the RTL unit test:

```sh
bash tests/run_predictor_tests.sh +show_counters
```

Counters start at `01`. Taken branches increment toward `11`; not-taken branches
decrement toward `00`. They stop at those limits. The upper bit is the prediction.

| Mode | Index, with compressed instructions disabled |
|---|---|
| Shared | `PC[9:2]` |
| Task-aware, 3 tasks + scheduler | `{context_id[1:0], PC[7:2]}` |

The bimodal table always has 256 counters, split into one bank per context
(rounded up to a power of two): four 64-counter banks for 3 tasks.

The scheduler writes CSR `0xBC0`: bits 7:0 are the context ID, bit 8 enables the
task-aware mode. Tasks use IDs `0` through `TASKS-1` and the scheduler uses `TASKS`;
an out-of-range ID writes back as zero.
The lookup index travels with the branch so a later switch cannot change its
update destination.

- Predictor RTL: [bimodal](../../src/ifu/bpred/taskTwoBitPredictor.sv) and [gshare](../../src/ifu/bpred/taskGshare.sv)
- [Scheduler](sw/workload.c) and [context switch](sw/context.S)
- Results: `results/twobit-tasks-3/report.md` and `results/gshare-tasks-3/report.md`
- [Memory map, measurement definitions, and limitations](DESIGN.md)
