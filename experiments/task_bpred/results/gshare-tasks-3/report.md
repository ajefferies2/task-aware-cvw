# Task-aware branch prediction: measured results

18 successful full-core RTL runs. Every paired run passed software self-checks and matched checksums, retired instructions, conditional-branch counts, hot-branch counts, and task-ID changes.

gshare. Task-aware mode gives each context its own global history; all contexts share the counters. Mode 0 is the same predictor with one shared history and table.

Tasks: 3, plus the scheduler in its own predictor context (4 contexts). Direction table: 256 two-bit counters in either mode; banked modes use 4 banks of 64 counters, with 0 unused banks. BTB: 1,024 entries, shared and identical in both modes. RAS: 16 entries, shared and identical.

| Workload | Quantum | Shared hot accuracy | Task-aware hot accuracy | Shared scheduler misses | Task-aware scheduler misses | Shared cycles | Task-aware cycles | Cycle reduction |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| opposite_shared_pc | 1 | 66.62% | 99.93% | 2063 | 18 | 882951 | 874753 | +0.93% |
| opposite_shared_pc | 16 | 97.80% | 99.87% | 262 | 18 | 154653 | 153865 | +0.51% |
| opposite_shared_pc | 256 | 99.76% | 99.87% | 22 | 18 | 107853 | 107785 | +0.06% |
| opposite_separate_pc | 1 | 33.33% | 33.33% | 2063 | 18 | 899346 | 895258 | +0.45% |
| opposite_separate_pc | 16 | 95.72% | 95.70% | 263 | 17 | 155948 | 155414 | +0.34% |
| opposite_separate_pc | 256 | 99.63% | 99.61% | 23 | 17 | 107948 | 107894 | +0.05% |
| embench | 500 | 86.27% | 90.35% | 2635 | 574 | 6467030 | 6437311 | +0.46% |
| embench | 8000 | 90.77% | 91.03% | 236 | 159 | 4275266 | 4272821 | +0.06% |
| embench | 128000 | 91.79% | 91.80% | 30 | 59 | 4158145 | 4158064 | +0.00% |

Quantum is workload iterations per task slice, except for `embench`, where it is task cycles per timer tick. Cycle counts include scheduler overhead. Hot accuracy counts only the explicitly labeled conditional branch in each workload iteration; for `embench` it counts every task branch. Scheduler misses are direction mispredictions in the scheduler's own context. Negative cycle reduction means task-aware mode was slower.

The shared-PC workload intentionally runs opposing task-dependent outcomes through the same code; the separate-PC workload is its control. Embench runs real kernels under timer preemption.

See [../../README.md](../../README.md) for implementation, commands, and measurement definitions.
