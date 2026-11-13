# Task-aware branch prediction

Alex Jefferies and Alec Saldana — CPE5300

A [CORE-V Wally](https://github.com/openhwfoundation/cvw) experiment comparing:

- **Shared:** 256 two-bit branch counters.
- **Task-aware:** the same counters split into two 128-entry banks.

Two cooperative tasks run four workloads in Verilator. A custom CSR selects the
current task. The branch-target buffer and return stack stay shared.

```sh
cd experiments/task_bpred
make test CROSS_COMPILE=riscv64-unknown-elf-
python3 run_experiments.py
```

Requires Verilator, a C++ compiler, Make, Python, and RISC-V GCC/binutils.
Matplotlib is optional (`--no-plot`). Set `CROSS_COMPILE` to your compiler prefix;
omitting it uses the local Zephyr SDK path.

[Results](experiments/task_bpred/results/report.md) ·
[Plots](experiments/task_bpred/results/comparison.png) ·
[Code and counter demo](experiments/task_bpred/README.md) ·
[Design notes](experiments/task_bpred/DESIGN.md)

40 comparison runs and directed tests pass. Simulation only; FPGA testing and
the full upstream architectural regression remain undone. See [LICENSE](LICENSE).
