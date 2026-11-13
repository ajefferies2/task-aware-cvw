#!/usr/bin/env python3
"""Run matched shared/partitioned Wally experiments and save reproducible results."""
import argparse
import csv
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORKLOADS = {0: "opposite_shared_pc", 1: "structured", 2: "pseudorandom", 3: "opposite_separate_pc"}


def arguments():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, default=ROOT / "build/obj_dir/Vtask_bpred_tb")
    p.add_argument("--mem", type=Path, default=ROOT / "sw/build/workloads.mem")
    p.add_argument("--symbols", type=Path, default=ROOT / "sw/build/workloads.nm")
    p.add_argument("--output", type=Path, default=ROOT / "results")
    p.add_argument("--quanta", type=int, nargs="+", default=[1, 4, 16, 64, 256])
    p.add_argument("--workloads", type=int, nargs="+", choices=WORKLOADS, default=list(WORKLOADS))
    p.add_argument("--iterations", type=int, default=2048)
    p.add_argument("--timeout", type=int, default=120)
    p.add_argument("--repeat", type=int, default=1)
    p.add_argument("--window", type=int, default=32, help="hot branches measured after each task-ID change")
    p.add_argument("--maxcycles", type=int, default=10000000)
    p.add_argument("--no-plot", action="store_true")
    args = p.parse_args()
    if min(args.quanta + [args.iterations, args.timeout, args.repeat, args.window, args.maxcycles]) < 1:
        p.error("quanta, iterations, timeout, and repeat must be positive")
    return args


def run_case(args, workload, quantum, mode, repeat):
    # Record commands relative to the experiment so published results are portable.
    cmd = ["./" + os.path.relpath(args.binary.resolve(), ROOT),
           f"+mem={os.path.relpath(args.mem.resolve(), ROOT)}",
           f"+mode={mode}", f"+quantum={quantum}", f"+workload={workload}",
           f"+iterations={args.iterations}", f"+window={args.window}", f"+maxcycles={args.maxcycles}"]
    symbols = {}
    for line in args.symbols.read_text().splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    for task in (0, 1):
        prefix = f"task{task}_hot" if workload == 3 else "hot"
        for boundary in ("start", "end"):
            cmd.append(f"+hot{task}_{boundary}={symbols[prefix + '_' + boundary]:x}")
    stem = f"w{workload}_q{quantum}_m{mode}_r{repeat}"
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=args.timeout)
    (args.output / f"{stem}.log").write_text(result.stdout + result.stderr)
    records = [line.removeprefix("RESULT ") for line in result.stdout.splitlines() if line.startswith("RESULT ")]
    if result.returncode or len(records) != 1:
        raise RuntimeError(f"{stem}: simulation failed; see {args.output / (stem + '.log')}")
    row = json.loads(records[0])
    if row.get("status") not in (1, "pass", "PASS"):
        raise RuntimeError(f"{stem}: software self-check failed: {row}")
    if row.get("hot_branches") != 2 * args.iterations:
        raise RuntimeError(f"{stem}: expected {2 * args.iterations} controlled branches, got {row.get('hot_branches')}")
    for prefix in ("", "hot_", "post_switch_"):
        if not 0 <= row[prefix + "mispredictions"] <= row[prefix + "branches"]:
            raise RuntimeError(f"{stem}: inconsistent {prefix} counters")
        if sum(t[prefix + "branches"] for t in row["per_task"]) != row[prefix + "branches"]:
            raise RuntimeError(f"{stem}: inconsistent per-task {prefix} branch totals")
        if sum(t[prefix + "mispredictions"] for t in row["per_task"]) != row[prefix + "mispredictions"]:
            raise RuntimeError(f"{stem}: inconsistent per-task {prefix} miss totals")
    for task in row.get("per_task", []):
        if task["hot_branches"] != args.iterations:
            raise RuntimeError(f"{stem}: incorrect per-task branch attribution: {task}")
    row.update(workload=workload, workload_name=WORKLOADS[workload], quantum=quantum,
               mode=mode, iterations=args.iterations, repeat=repeat, window=args.window, command=cmd)
    return row


def accuracy(row, prefix=""):
    n = row.get(prefix + "branches", 0)
    return 100 * (1 - row[prefix + "mispredictions"] / n) if n else None


def validate_pair(shared, partitioned):
    # Prediction can change timing, never architectural results or retired work.
    for key in ("checksum", "checksum0", "checksum1", "instructions", "branches", "hot_branches", "switches", "predictor_entries", "btb_entries", "ras_entries"):
        if key in shared and shared[key] != partitioned[key]:
            raise RuntimeError(f"Unequal {key} in matched pair: {shared[key]} != {partitioned[key]}")


def plot(rows, output):
    os.environ.setdefault("MPLCONFIGDIR", str(output / ".matplotlib"))
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    workloads = sorted({r["workload"] for r in rows})
    fig, axes = plt.subplots(len(workloads), 2, figsize=(10, 3 * len(workloads)), squeeze=False)
    for axrow, workload in zip(axes, workloads):
        entries = rows[0]["predictor_entries"]
        for mode, label in [(0, f"Shared: {entries} counters"), (1, f"Partitioned: 2 x {entries // 2} counters")]:
            subset = sorted((r for r in rows if r["workload"] == workload and r["mode"] == mode and r["repeat"] == 0), key=lambda r: r["quantum"])
            x = [r["quantum"] for r in subset]
            axrow[0].plot(x, [accuracy(r, "hot_") for r in subset], marker="o", label=label)
            axrow[1].plot(x, [r["cycles"] for r in subset], marker="o", label=label)
        for ax in axrow:
            ax.set_xscale("log", base=2)
            ax.set_xlabel("Iterations per task slice")
            ax.set_title(WORKLOADS[workload].replace("_", " "))
            ax.grid(alpha=.25)
        axrow[0].set_ylabel("Hot conditional-branch accuracy (%)")
        axrow[0].set_ylim(0, 101)
        axrow[1].set_ylabel("Measured processor cycles")
    axes[0][0].legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(output / "comparison.png", dpi=160)
    fig.savefig(output / "comparison.pdf")
    plt.close(fig)


def report(rows, output):
    hardware = rows[0]
    entries = hardware["predictor_entries"]
    lines = ["# Task-aware branch prediction: measured results", "",
             f"{len(rows)} successful full-core RTL runs. Every paired run passed software self-checks and matched checksums, retired instructions, conditional-branch counts, hot-branch counts, and task-ID changes.", "",
             f"Direction table: {entries} two-bit counters in either mode; partitioned mode assigns {entries // 2} counters per task. BTB: {hardware['btb_entries']:,} entries, shared and identical in both modes. RAS: {hardware['ras_entries']} entries, shared and identical.", "",
             "| Workload | Quantum | Shared hot accuracy | Partitioned hot accuracy | Shared cycles | Partitioned cycles | Cycle reduction |",
             "|---|---:|---:|---:|---:|---:|---:|"]
    for shared, partitioned in zip(rows[::2], rows[1::2]):
        if shared["repeat"] != 0:
            continue
        reduction = 100 * (shared["cycles"] - partitioned["cycles"]) / shared["cycles"]
        lines.append(f"| {shared['workload_name']} | {shared['quantum']} | {accuracy(shared, 'hot_'):.2f}% | {accuracy(partitioned, 'hot_'):.2f}% | {shared['cycles']} | {partitioned['cycles']} | {reduction:+.2f}% |")
    lines += ["", "Quantum is workload iterations per task slice. Cycle counts include scheduler overhead. Hot accuracy counts only the explicitly labeled conditional branch in each workload iteration. Negative cycle reduction means partitioning was slower.", "",
              "The shared-PC workload intentionally runs opposing task-dependent outcomes through the same code. It demonstrates a mechanism, not a representative benchmark average. Structured and pseudorandom cases and the separate-PC control expose limitations. These measurements do not establish effects for desktop process switches, preemptive scheduling, global-history predictors, or FPGA timing.", "",
              "`results.json` contains per-task, post-switch, direction-miss, target-miss, and actual control-redirection counters. The post-switch window covers the first configured number of hot branches following each task-ID change. Initial startup is excluded from that window; predictor training during startup is retained.", "",
              f"See [{os.path.relpath(ROOT / 'README.md', output)}]({os.path.relpath(ROOT / 'README.md', output)}) for implementation, commands, and measurement definitions."]
    (output / "report.md").write_text("\n".join(lines) + "\n")


def main():
    args = arguments()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    for path in (args.binary, args.mem, args.symbols):
        if not path.is_file():
            sys.exit(f"Missing {path}; run make in {ROOT} first")
    metadata = {"iterations": args.iterations, "quanta": args.quanta,
                "workloads": args.workloads, "repeat": args.repeat, "window": args.window,
                "sha256": {os.path.relpath(p.resolve(), ROOT): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in (args.binary, args.mem, args.symbols)},
                "verilator": subprocess.check_output(["verilator", "--version"], text=True).strip()}
    (args.output / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    rows = []
    for repeat in range(args.repeat):
        for workload in args.workloads:
            for quantum in args.quanta:
                pair = [run_case(args, workload, quantum, mode, repeat) for mode in (0, 1)]
                validate_pair(*pair)
                if repeat:
                    for row in pair:
                        first = next(r for r in rows if r["repeat"] == 0 and r["workload"] == workload and r["quantum"] == quantum and r["mode"] == row["mode"])
                        for key, value in row.items():
                            if key not in ("repeat", "command") and first[key] != value:
                                raise RuntimeError(f"Nondeterministic {key} for workload={workload}, quantum={quantum}, mode={row['mode']}")
                rows.extend(pair)
                for row in pair:
                    row["accuracy_pct"] = accuracy(row)
                    row["hot_accuracy_pct"] = accuracy(row, "hot_")
                    row["post_switch_accuracy_pct"] = accuracy(row, "post_switch_")
                    print(f"{row['workload_name']:22s} q={quantum:4d} mode={row['mode']} cycles={row['cycles']:8d} hot_accuracy={row['hot_accuracy_pct']:.2f}%", flush=True)
                (args.output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    keys = sorted({k for row in rows for k, v in row.items() if not isinstance(v, (dict, list))})
    with (args.output / "results.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, keys, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    if not args.no_plot:
        plot(rows, args.output)
    report(rows, args.output)
    print(f"Validated {len(rows)} simulations. Results: {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
