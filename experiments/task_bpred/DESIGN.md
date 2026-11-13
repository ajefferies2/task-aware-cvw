# Task-aware branch prediction on CORE-V Wally

This experiment runs the actual five-stage Wally RTL in Verilator. A configurable
number of cooperatively scheduled tasks compare a shared two-bit direction predictor with
a task-partitioned predictor at equal storage capacity. No full Wally toolchain
installation, Linux image, commercial simulator, or FPGA is needed.

## Run

From the Wally repository root:

```sh
cd experiments/task_bpred
make test
python3 run_experiments.py

# Build and measure eight tasks instead of the default two.
make TASKS=8 test
python3 run_experiments.py --tasks 8
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
Build products stay under `build/tasks-N/` and `sw/build/tasks-N/`, so switching
task counts cannot reuse a binary built for a different count. `--tasks` selects
an already compiled configuration; it does not change the hardware at runtime.
The default two-task sweep writes `results/`; other counts write
`build/tasks-N/results/` unless `--output` is given. No system setup files change.

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
The runner chooses a watchdog limit based on task count and requested work;
`--maxcycles` overrides it.

## Hardware change

The experiment config is in `config/config.vh`: RV32 with integer multiply/divide,
CSRs, performance counters, instruction ROM and data RAM, and no caches or
external bus. Compressed instructions are disabled for this experiment.
The testbench loads the same initial image into separate instruction and data
memories at `0x80000000`. Instruction ROM is 64 KiB. Data RAM is the next power of
two at least as large as `max(65536, 4096*TASKS + 32768)` bytes. Its top 4 KiB holds
the mailbox and per-task results; the preceding 4 KiB is the scheduler stack.
This is a simulation memory model, not a completed board integration.

The new `BP_TASK_TWOBIT` option selects
[`taskTwoBitPredictor.sv`](../../src/ifu/bpred/taskTwoBitPredictor.sv).
Existing Wally configurations retain their original predictor choices.

| Mode | Direction-table indexing | Storage |
|---|---|---|
| Shared | Eight PC index bits | 256 two-bit counters |
| Partitioned | Task ID above the remaining low PC index bits | `banks` banks of `256/banks` two-bit counters |

`TASKS` accepts 1–256 and defaults to 2. The build passes it to Wally's
`P.BPRED_TASKS` parameter and the software's `TASK_COUNT` macro. Let
`b = ceil(log2(TASKS))` and `banks = 2**b`. Partitioned lookup is
`(task_id << (8-b)) | (PC_index & ((256/banks)-1))`. With one task the entire
PC index remains; with 256 tasks each task has one counter. Counts that are not
powers of two leave the excess banks unused. The full 256-counter table is
allocated in both modes, including unused banks.

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
| 7:0 | Task ID: 0 through `TASKS-1` |
| 8 | Mode: 0 shared, 1 partitioned |
| Others | Ignored on write; read as zero |

An out-of-range task ID is mapped to zero; the mode bit is still applied. The
internal task-ID bus uses `max(1, ceil(log2(TASKS)))` bits. The mode bit is stored
separately, so increasing the ID width cannot overwrite it. Builds with more
tasks than direction counters, more than 256 tasks, or zero tasks are rejected.

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
The scheduler visits every unfinished task in ID order. Even and odd task IDs
have opposite outcomes/phases in workloads 0, 1, and 3; workload 2 gives each task
a separate deterministic random seed.

| ID | Workload | Purpose |
|---|---|---|
| 0 | Opposite outcomes at the same conditional-branch PC | Controlled task interference in shared code |
| 1 | Eight-iteration taken/not-taken bursts, opposite phases | Structured behavior that need not favor partitioning |
| 2 | Deterministic xorshift outcomes with different task seeds | Pseudorandom control |
| 3 | Opposite outcomes at distinct, nonaliasing hot PCs | Control where shared prediction already separates tasks |

`sw/hot.S` explicitly emits each measured conditional branch, preventing the C
compiler from replacing it with arithmetic. Both paths execute equal instruction
counts. Separate-PC functions use a 20-byte stride: their five-word spacing visits
all 256 shared table indices before repeating. Symbol addresses identify only
those branches. Each hot step contributes 7
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
  the workload from this attribution choice. Each entry also contains its
  checksum, expected checksum, and completed iteration count.
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
larger than total work at 1, 2, 3, 8, and 256 tasks. The one-task case requires both
modes to produce identical timing and prediction results. Directed predictor and
CSR tests cover 1, 2, 3, 4, 8, 16, and 256 tasks, including all 256 CSR ID encodings:

```sh
bash tests/run_predictor_tests.sh --matrix
```

Original `rv32i` and `rv32imc` core configurations were also linted after the RTL
wiring change.

This does not replace the full upstream architectural regression. No Basys3
bitstream, FPGA timing/area result, preemptive RTOS, or per-task global-history
predictor is included. The report describes this two-bit direction experiment;
its results should not be generalized to all predictors or operating systems.
