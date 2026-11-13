#!/usr/bin/env bash
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$test_dir/../../.." && pwd)
build_dir="$test_dir/../build/unit_predictor"
mkdir -p "$build_dir"
verilator --binary --timing --assert -Wno-fatal --top-module tb_task_predictor \
  --Mdir "$build_dir" \
  "$repo_dir/src/generic/flop/flopenr.sv" \
  "$repo_dir/src/generic/flop/flopenrc.sv" \
  "$repo_dir/src/ifu/bpred/taskTwoBitPredictor.sv" \
  "$test_dir/tb_task_predictor.sv" > "$build_dir/build.log" 2>&1
"$build_dir/Vtb_task_predictor" "$@"
