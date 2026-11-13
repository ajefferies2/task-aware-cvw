# Task-aware branch prediction on CORE-V Wally

This experiment runs the actual five-stage Wally RTL in Verilator. Two
cooperatively scheduled tasks compare a shared two-bit direction predictor with
a task-partitioned predictor at equal storage capacity. No full Wally toolchain
installation, Linux image, commercial simulator, or FPGA is needed.

## Run

From the Wally repository root:

```sh
cd experiments/task_bpred
make test
python3 run_experiments.py
```

`make test` builds the processor simulator and bare-metal software, runs directed
predictor tests, and executes a small matrix of both predictor modes. The Python
command runs 40 simulations: four workloads, five task quanta, and two modes,
with 2,048 workload iterations per task. It writes
[results/report.md](results/report.md), [results/results.csv](results/results.csv),
[results/results.json](results/results.json), and comparison PNG/PDF plots.
Each matched pair must have equal checksums, retired instructions, branch counts,
controlled hot-branch counts, and task-ID changes. Each task must execute exactly
the requested number of controlled branches.

Required tools are Verilator, a host C++ compiler, Make, Python 3, and a bare-metal
RISC-V GCC/binutils toolchain. Matplotlib is needed only for plots; use `--no-plot`
to skip them. The default compiler prefix uses the existing local Zephyr SDK:

```text
/opt/zephyr-sdk/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-
```

Override it for another installation:

```sh
make CROSS_COMPILE=riscv64-unknown-elf-
```

The software uses `-march=rv32im_zicsr_zifencei -mabi=ilp32`, its own startup and
linker script, and no libc. The `riscv64` compiler name does not imply RV64 output.
Build products stay under `build/` and `sw/build/`. No system setup files change.

Useful commands:

```sh
make run                                      # one matched smoke-test pair
python3 run_experiments.py --quanta 1 7 64 --iterations 127
python3 run_experiments.py --window 8 --output build/window8
python3 run_experiments.py --workloads 0 --quanta 16 --repeat 2 --no-plot --output build/repeat
```

For a waveform, take a command from a result's `command` field in `results.json`
and append `+trace=build/run.vcd`, then open it with `gtkwave build/run.vcd`.
The simulator accepts `+maxcycles=N` and aborts on timeout or a software failure.

## Hardware change

The experiment config is in `config/config.vh`: RV32 with integer multiply/divide,
CSRs, performance counters, instruction ROM and data RAM, and no caches or
external bus. Compressed instructions are disabled for this experiment.
The testbench loads the same initial image into separate instruction and data
memories at `0x80000000` in a 64 KiB address window. This is a simulation memory
model, not a completed board integration.

The new `BP_TASK_TWOBIT` option selects
[`taskTwoBitPredictor.sv`](../../src/ifu/bpred/taskTwoBitPredictor.sv).
Existing Wally configurations retain their original predictor choices.

| Mode | Direction-table indexing | Storage |
|---|---|---|
| Shared | Eight PC index bits | 256 two-bit counters |
| Partitioned | Task ID concatenated with seven PC index bits | Two banks of 128 two-bit counters |

Both use the same physical 512-bit direction table. The branch target buffer
stays at Wally's default 1,024 entries and the return-address stack at 16 entries;
both remain shared and unchanged across modes. Wally's existing instruction-class
prediction logic also remains enabled. Only direction state is task-partitioned.
The shared baseline is the new module with partitioning disabled, so counter
updates and reset behavior are identical in the two modes. Both execute the same
CSR writes and scheduler code.

The custom machine CSR `0xBC0` exists only when this predictor is enabled:

| Bits | Meaning |
|---|---|
| 0 | Task ID: 0 or 1 |
| 8 | Mode: 0 shared, 1 partitioned |
| Others | Ignored on write; read as zero |

The scheduler writes it before dispatch. Existing CSR serialization flushes and
refetches younger instructions; new-context forwarding handles the fetch on the
write edge. The predictor carries the lookup index through the pipeline, so an
in-flight branch updates its original bank. Updates occur once when an accepted
branch leaves the memory stage. They use the current counter value, avoiding
lost updates when adjacent branches alias. Reset initializes counters to weakly
not taken. RTL uses synthesizable registers; FPGA resource use/timing is unmeasured.

## Software and workloads

`sw/context.S` saves/restores `ra`, `sp`, and `s0`–`s11`, as required for cooperative
calls. Each task has its own 4 KiB stack. Task-local variables and branch behavior
survive yields. This is a cooperative scheduler, not interrupt-driven preemption;
a quantum is a number of workload iterations, not cycles or instructions.

| ID | Workload | Purpose |
|---|---|---|
| 0 | Opposite outcomes at the same conditional-branch PC | Controlled task interference in shared code |
| 1 | Eight-iteration taken/not-taken bursts, opposite phases | Structured behavior that need not favor partitioning |
| 2 | Deterministic xorshift outcomes with different task seeds | Pseudorandom control |
| 3 | Opposite outcomes at distinct, nonaliasing hot PCs | Control where shared prediction already separates tasks |

`sw/hot.S` explicitly emits each measured conditional branch, preventing the C
compiler from replacing it with arithmetic. Both paths execute equal instruction
counts. Symbol ranges identify only those branches. Each hot step contributes 7
or 3 to a checksum, checked against an independent arithmetic reference after
measurement. Completed iteration counts and CSR task identity are also checked.
The shared-PC example models different task state through common code; it is
not evidence about two independently linked desktop programs.

## Measurement definitions

- `cycles`, `instructions`, `branches`, and `mispredictions` cover the gated
  scheduler interval. Mispredictions here mean conditional **direction** errors.
- `hot_*` covers only the labeled workload conditional branches, one per
  iteration. This separates task behavior from loop and scheduler branches.
- `post_switch_*` covers the first `--window` hot branches after each observed
  task-ID change. A shorter slice ends the window early; a new switch restarts it.
  Initial startup is not counted as a context switch.
- `full_control_mispredictions` counts Wally's actual wrong-next-PC reports over
  all accepted instructions; `hot_control_mispredictions` restricts that to hot
  branches. Direction errors and actual redirects are different measurements.
- Target-error counters expose interference in the shared BTB. Correct direction
  alone does not guarantee a correct target or a cycle saving.
- `per_task` uses the context carried alongside each instruction. Scheduler
  instructions execute under the most recent task's context. Hot counts isolate
  the workload from this attribution choice.
- `switches` counts actual task-ID changes; `software_switches` counts dispatches
  and therefore includes the initial dispatch to task 0.
- Software `mcycle`/`minstret` deltas bracket a slightly wider interval than the
  testbench gate. Use the testbench `cycles` field for the reported comparison.

Counters qualify accepted memory-stage instructions with valid, stall, and flush
signals, avoiding repeated counting during stalls. Every run resets the CPU, but
the pre-measurement smoke test/setup trains the predictor. Results are not a
pristine-table cold-start experiment. Runs are deterministic; repeated runs test
reproducibility rather than provide independent statistical samples.

## Verification and scope

Directed predictor tests cover saturation, shared interference, partition
isolation, equal capacity, original-task updates after a switch, adjacent aliasing
updates, stalls, and squashed branches. Software smoke checks exercise arithmetic,
load/store sizes, signed/unsigned branches, calls/returns, multiply/divide, counters,
and CSR readback/masking. End-to-end cases include partial final slices and quanta
larger than total work. Original `rv32i` and `rv32imc` core configurations were
also linted after the RTL wiring change.

This does not replace the full upstream architectural regression. No Basys3
bitstream, FPGA timing/area result, preemptive RTOS, or per-task global-history
predictor is included. The report describes this two-bit direction experiment;
its results should not be generalized to all predictors or operating systems.
