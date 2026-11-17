#!/bin/sh
# Rebuild and run the study: 3 tasks, bimodal and gshare predictors. Each run
# covers the shared-branch workload, its control, and preemptive Embench.
# Summaries go to results/<predictor>-tasks-3/.
# Needs Verilator, the Zephyr SDK 0.17.4 compiler (set CROSS_COMPILE if it is
# not in /opt/zephyr-sdk), and `git submodule update --init addins/embench-iot`.
set -e
cd "$(dirname "$0")"
make software TASKS=3
for predictor in twobit gshare; do
  make sim TASKS=3 PREDICTOR=$predictor
  python3 run_experiments.py --tasks 3 --predictor $predictor --no-plot --output results/$predictor-tasks-3
done
