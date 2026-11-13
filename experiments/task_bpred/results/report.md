# Task-aware branch prediction: measured results

40 successful full-core RTL runs. Every paired run passed software self-checks and matched checksums, retired instructions, conditional-branch counts, hot-branch counts, and task-ID changes.

Direction table: 256 two-bit counters in either mode; partitioned mode assigns 128 counters per task. BTB: 1,024 entries, shared and identical in both modes. RAS: 16 entries, shared and identical.

| Workload | Quantum | Shared hot accuracy | Partitioned hot accuracy | Shared cycles | Partitioned cycles | Cycle reduction |
|---|---:|---:|---:|---:|---:|---:|
| opposite_shared_pc | 1 | 0.00% | 99.98% | 526446 | 518268 | +1.55% |
| opposite_shared_pc | 4 | 50.02% | 99.98% | 188010 | 183928 | +2.17% |
| opposite_shared_pc | 16 | 87.52% | 99.98% | 99306 | 98296 | +1.02% |
| opposite_shared_pc | 64 | 96.90% | 99.98% | 77130 | 76888 | +0.31% |
| opposite_shared_pc | 256 | 99.24% | 99.98% | 71586 | 71536 | +0.07% |
| structured | 1 | 25.00% | 75.07% | 528488 | 524392 | +0.78% |
| structured | 4 | 62.48% | 75.07% | 191084 | 190060 | +0.54% |
| structured | 16 | 87.48% | 75.07% | 103404 | 104428 | -0.99% |
| structured | 64 | 78.10% | 75.07% | 82764 | 83020 | -0.31% |
| structured | 256 | 75.76% | 75.07% | 77604 | 77668 | -0.08% |
| pseudorandom | 1 | 49.98% | 49.34% | 530542 | 530604 | -0.01% |
| pseudorandom | 4 | 49.68% | 49.34% | 196228 | 196264 | -0.02% |
| pseudorandom | 16 | 50.22% | 49.34% | 110552 | 110632 | -0.07% |
| pseudorandom | 64 | 49.51% | 49.34% | 89202 | 89224 | -0.02% |
| pseudorandom | 256 | 49.44% | 49.34% | 83856 | 83872 | -0.02% |
| opposite_separate_pc | 1 | 99.98% | 99.98% | 526460 | 526472 | -0.00% |
| opposite_separate_pc | 4 | 99.98% | 99.98% | 185978 | 185988 | -0.01% |
| opposite_separate_pc | 16 | 99.98% | 99.98% | 98810 | 98820 | -0.01% |
| opposite_separate_pc | 64 | 99.98% | 99.98% | 77018 | 77028 | -0.01% |
| opposite_separate_pc | 256 | 99.98% | 99.98% | 71570 | 71580 | -0.01% |

Quantum is workload iterations per task slice. Cycle counts include scheduler overhead. Hot accuracy counts only the explicitly labeled conditional branch in each workload iteration. Negative cycle reduction means partitioning was slower.

The shared-PC workload intentionally runs opposing task-dependent outcomes through the same code. It demonstrates a mechanism, not a representative benchmark average. Structured and pseudorandom cases and the separate-PC control expose limitations. These measurements do not establish effects for desktop process switches, preemptive scheduling, global-history predictors, or FPGA timing.

`results.json` contains per-task, post-switch, direction-miss, target-miss, and actual control-redirection counters. The post-switch window covers the first configured number of hot branches following each task-ID change. Initial startup is excluded from that window; predictor training during startup is retained.

See [../README.md](../README.md) for implementation, commands, and measurement definitions.
