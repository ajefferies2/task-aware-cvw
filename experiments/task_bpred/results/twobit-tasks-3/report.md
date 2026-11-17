# Task-aware branch prediction: measured results

18 successful full-core RTL runs. Every paired run passed software self-checks and matched checksums, retired instructions, conditional-branch counts, hot-branch counts, and task-ID changes.

Bimodal two-bit predictor. Task-aware mode gives each context its own bank of counters. Mode 0 is the same predictor with one shared history and table.

Tasks: 3, plus the scheduler in its own predictor context (4 contexts). Direction table: 256 two-bit counters in either mode; banked modes use 4 banks of 64 counters, with 0 unused banks. BTB: 1,024 entries, shared and identical in both modes. RAS: 16 entries, shared and identical.

| Workload | Quantum | Shared hot accuracy | Task-aware hot accuracy | Shared scheduler misses | Task-aware scheduler misses | Shared cycles | Task-aware cycles | Cycle reduction |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| opposite_shared_pc | 1 | 66.63% | 99.97% | 2054 | 2052 | 882849 | 878773 | +0.46% |
| opposite_shared_pc | 16 | 91.65% | 99.97% | 134 | 132 | 154781 | 153775 | +0.65% |
| opposite_shared_pc | 256 | 99.46% | 99.97% | 14 | 12 | 107741 | 107695 | +0.04% |
| opposite_separate_pc | 1 | 99.97% | 99.97% | 2054 | 2052 | 891060 | 891084 | -0.00% |
| opposite_separate_pc | 16 | 99.97% | 99.97% | 134 | 132 | 154546 | 154566 | -0.01% |
| opposite_separate_pc | 256 | 99.97% | 99.97% | 14 | 12 | 107746 | 107766 | -0.02% |
| embench | 500 | 92.20% | 92.19% | 8495 | 8483 | 6453213 | 6434431 | +0.29% |
| embench | 8000 | 93.07% | 92.19% | 670 | 442 | 4276613 | 4267629 | +0.21% |
| embench | 128000 | 93.64% | 92.19% | 54 | 40 | 4162323 | 4155644 | +0.16% |

Quantum is workload iterations per task slice, except for `embench`, where it is task cycles per timer tick. Cycle counts include scheduler overhead. Hot accuracy counts only the explicitly labeled conditional branch in each workload iteration; for `embench` it counts every task branch. Scheduler misses are direction mispredictions in the scheduler's own context. Negative cycle reduction means task-aware mode was slower.

The shared-PC workload intentionally runs opposing task-dependent outcomes through the same code; the separate-PC workload is its control. Embench runs real kernels under timer preemption.

See [../../README.md](../../README.md) for implementation, commands, and measurement definitions.
