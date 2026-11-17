# Task-aware branch prediction on CORE-V Wally

This experiment runs the actual five-stage Wally RTL in Verilator. A configurable
number of cooperatively scheduled tasks compare a shared two-bit direction predictor with
a task-partitioned predictor at equal storage capacity. No full Wally toolchain
installation, Linux image, commercial simulator, or FPGA is needed.

## Run

From the Wally repository root:

```sh
cd experiments/task_bpred
make test        # unit tests plus a short matrix in both modes
./sweep.sh       # the study: 3 tasks, both predictors, into results/<config>/
```

`run_experiments.py` runs one built configuration. By default it runs the
shared-branch workload (0) and its control (3) at three quanta, and the
preemptive Embench workload (4) at three timer quanta, each in both modes
(18 simulations). Workloads 1 and 2 remain available with `--workloads`.
It writes `report.md`, `results.csv`, `results.json`, and optional plots.
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
Alex's results were built with Zephyr SDK 0.17.4 (GCC 12.2.0); that compiler
reproduces his program image byte for byte. SDK 1.0.x injects its own linker
script and places code at the wrong address.

Simulators are built per configuration under `build/<PREDICTOR>-tasks-<N>/`;
software under `sw/build/tasks-N/`. `--tasks` and `--predictor` select
an already compiled configuration and are checked against the hardware; they do
not change it at runtime. Sweeps write `build/<config>/results/` unless `--output`
is given. No system setup files change.

Useful commands:

```sh
make run                                      # one matched smoke-test pair
make sim TASKS=3 PREDICTOR=gshare            # 3 tasks, task-aware gshare
python3 run_experiments.py --tasks 3 --predictor gshare
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

`PREDICTOR` selects the direction predictor; both have 256 counters:

| `PREDICTOR` | Type | Task-aware mode (CSR bit 8 set) |
|---|---|---|
| `twobit` (default) | `BP_TASK_TWOBIT`, [`taskTwoBitPredictor.sv`](../../src/ifu/bpred/taskTwoBitPredictor.sv) | Each context indexes its own bank of counters |
| `gshare` | `BP_TASK_GSHARE`, [`taskGshare.sv`](../../src/ifu/bpred/taskGshare.sv) | Each context has its own global history; the table is shared |

With bit 8 clear, `taskGshare` is Wally's `gshare`: one history register and one
table. A context write flushes all younger instructions, and older branches have
committed their history by then, so the current context selects the history.
Existing Wally configurations retain their original predictor choices.

The scheduler runs under its own context, ID `TASKS`, so the hardware has
`TASKS + 1` contexts. The description below uses "tasks" for these contexts.

| Mode | Direction-table indexing | Storage |
|---|---|---|
| Shared | Eight PC index bits | 256 two-bit counters |
| Partitioned | Task ID above the remaining low PC index bits | `banks` banks of `256/banks` two-bit counters |

`TASKS` accepts 1–255 and defaults to 2. The build passes `TASKS + 1` to Wally's
`P.BPRED_TASKS` parameter and `TASKS` to the software's `TASK_COUNT` macro. Let
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
| 4 | One Embench-IoT kernel per task, preempted by a timer interrupt | Real code with many branches, scheduled like an RTOS |

`sw/hot.S` explicitly emits each measured conditional branch, preventing the C
compiler from replacing it with arithmetic. Both paths execute equal instruction
counts. Separate-PC functions use a 20-byte stride: their five-word spacing visits
all 256 shared table indices before repeating. Symbol addresses identify only
those branches. Each hot step contributes 7
or 3 to a checksum, checked against an independent arithmetic reference after
measurement. Completed iteration counts and CSR task identity are also checked.
The shared-PC example models different task state through common code; it is
not evidence about two independently linked desktop programs.

### Preemptive Embench workload (4)

Workload 4 runs real benchmark code under preemptive scheduling. Task `i` runs
the `i`th of three Embench-IoT kernels: `crc32` (a regular loop), `statemate`
(a state machine), and `nsichneu` (very branchy control code). Each task uses a
different kernel because kernels keep static state, so the workload supports at
most 3 tasks.
Each kernel is compiled from Wally's `addins/embench-iot` submodule
(`git submodule update --init addins/embench-iot`) through a generated wrapper
that exposes its static `benchmark_body()`; every other symbol is made local.
A task runs its kernel `--embench-reps` times, one repetition per call, and
verifies every result. `sw/minilibc.c` supplies `memcpy`, `memset`, and `memcmp`.

The testbench counts cycles spent in task code and raises Wally's machine timer
interrupt after `--embench-quanta` cycles, clearing it when the core takes the
trap, like an RTOS tick. `sw/preempt.S` saves all registers on the task's stack.
`preempt_schedule()` in `sw/preempt.c` switches to the scheduler context, picks
the next unfinished task round robin, and sets that task's context just before
`mret`. A finished task issues `ecall` and is not scheduled again; `main` starts
the run with `ecall` and resumes when all tasks finish. RAM is at least 128 KiB
to hold the kernels' data and both schedulers' stacks.

Because the timer counts cycles, a faster predictor sees fewer ticks. Matched
pairs therefore must agree on each task's work (branches, outcomes, verified
results) but not on totals that include scheduler work. For this workload the
`hot_*` counters cover every task branch, and the post-switch window covers the
first `--window` task branches after each task switch.

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
  instructions execute under the scheduler's own context and are reported as
  `kernel_branches` and `kernel_mispredictions`. Each entry also contains its
  checksum, expected checksum, and completed iteration count.
- `switches` counts changes from one task to a different task; entering the
  scheduler is not a switch. `software_switches` counts dispatches and therefore
  includes the initial dispatch to task 0.
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
