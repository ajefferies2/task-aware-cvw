#!/usr/bin/env bash
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$test_dir/../../.." && pwd)
if [[ ${1:-} == --matrix ]]; then
  task_counts=(1 2 3 4 8 16 256)
  shift
else
  task_counts=("${TASKS:-2}")
fi
for task_count in "${task_counts[@]}"; do
  # Strip leading zeros before arithmetic so TASKS=08 is decimal eight.
  # Bound significant digits first to avoid shell integer overflow.
  if [[ ! $task_count =~ ^0*([1-9][0-9]{0,2})$ ]]; then
    echo 'TASKS must be an integer in 1..256' >&2
    exit 2
  fi
  task_count=$((10#${BASH_REMATCH[1]}))
  if (( task_count > 256 )); then
    echo 'TASKS must be an integer in 1..256' >&2
    exit 2
  fi
  build_dir="$test_dir/../build/unit_predictor/tasks_$task_count"
  mkdir -p "$build_dir"
  if ! verilator --binary --timing --assert -Wno-fatal --top-module tb_task_predictor \
    -GTASKS="$task_count" -I"$repo_dir/config/shared" --Mdir "$build_dir" \
    "$repo_dir/src/cvw.sv" \
    "$repo_dir/src/generic/flop/flopenr.sv" \
    "$repo_dir/src/generic/flop/flopenrc.sv" \
    "$repo_dir/src/privileged/csrm.sv" \
    "$repo_dir/src/ifu/bpred/taskTwoBitPredictor.sv" \
    "$test_dir/tb_task_csr.sv" "$test_dir/tb_task_predictor.sv" \
    > "$build_dir/build.log" 2>&1; then
    cat "$build_dir/build.log" >&2
    exit 1
  fi
  "$build_dir/Vtb_task_predictor" "$@"
done
