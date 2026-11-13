# Task-aware branch prediction: measured results

40 successful full-core RTL runs. Every paired run passed software self-checks and matched checksums, retired instructions, conditional-branch counts, hot-branch counts, and task-ID changes.

Tasks: 2. Direction table: 256 two-bit counters in either mode; partitioned mode reserves 2 banks of 128 counters, with 0 unused banks. BTB: 1,024 entries, shared and identical in both modes. RAS: 16 entries, shared and identical.

| Workload | Quantum | Shared hot accuracy | Partitioned hot accuracy | Shared cycles | Partitioned cycles | Cycle reduction |
|---|---:|---:|---:|---:|---:|---:|
| opposite_shared_pc | 1 | 0.00% | 99.98% | 563313 | 551041 | +2.18% |
| opposite_shared_pc | 4 | 50.02% | 99.98% | 197229 | 196215 | +0.51% |
| opposite_shared_pc | 16 | 87.52% | 99.98% | 101613 | 101367 | +0.24% |
| opposite_shared_pc | 64 | 96.90% | 99.98% | 77709 | 77655 | +0.07% |
| opposite_shared_pc | 256 | 99.24% | 99.98% | 71733 | 71727 | +0.01% |
| structured | 1 | 25.00% | 75.07% | 565355 | 557167 | +1.45% |
| structured | 4 | 62.48% | 75.07% | 200303 | 198261 | +1.02% |
| structured | 16 | 87.48% | 75.07% | 105711 | 106485 | -0.73% |
| structured | 64 | 78.10% | 75.07% | 83343 | 83541 | -0.24% |
| structured | 256 | 75.76% | 75.07% | 77751 | 77805 | -0.07% |
| pseudorandom | 1 | 49.98% | 49.37% | 567409 | 563375 | +0.71% |
| pseudorandom | 4 | 49.68% | 49.37% | 205447 | 208549 | -1.51% |
| pseudorandom | 16 | 50.22% | 49.37% | 112859 | 113701 | -0.75% |
| pseudorandom | 64 | 49.51% | 49.37% | 89781 | 89989 | -0.23% |
| pseudorandom | 256 | 49.44% | 49.37% | 84003 | 84061 | -0.07% |
| opposite_separate_pc | 1 | 99.98% | 99.98% | 563327 | 559247 | +0.72% |
| opposite_separate_pc | 4 | 99.98% | 99.98% | 195197 | 198277 | -1.58% |
| opposite_separate_pc | 16 | 99.98% | 99.98% | 101117 | 101893 | -0.77% |
| opposite_separate_pc | 64 | 99.98% | 99.98% | 77597 | 77797 | -0.26% |
| opposite_separate_pc | 256 | 99.98% | 99.98% | 71717 | 71773 | -0.08% |

Quantum is workload iterations per task slice. Cycle counts include scheduler overhead. Hot accuracy counts only the explicitly labeled conditional branch in each workload iteration. Negative cycle reduction means partitioning was slower.

The shared-PC workload intentionally runs opposing task-dependent outcomes through the same code. It demonstrates a mechanism, not a representative benchmark average. Structured and pseudorandom cases and the separate-PC control expose limitations. These measurements do not establish effects for desktop process switches, preemptive scheduling, global-history predictors, or FPGA timing.

`results.json` contains per-task, post-switch, direction-miss, target-miss, and actual control-redirection counters. The post-switch window covers the first configured number of hot branches following each task-ID change. Initial startup is excluded from that window; predictor training during startup is retained.

See [../README.md](../README.md) for implementation, commands, and measurement definitions.
