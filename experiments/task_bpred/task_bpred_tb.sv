// SPDX-License-Identifier: Apache-2.0
// Small deterministic simulation environment for the actual Wally pipeline.
`include "config.vh"
import cvw::*;

module task_bpred_tb;
  `include "parameter-defs.vh"
  // The hardware has one predictor context per task plus one for the scheduler.
  localparam int CONTEXTS = P.BPRED_TASKS;
  localparam int TASK_COUNT = CONTEXTS - 1;
  localparam int KERNEL_ID = TASK_COUNT;
  localparam int CONTEXT_WIDTH = P.BPRED_TASK_BITS + 1;
  localparam int BANKS = 2**$clog2(CONTEXTS);
  localparam int RAM_BYTES = int'(P.DTIM_RANGE) + 1;
  localparam int ARG_WORD = (RAM_BYTES - 32) / 4;
  localparam int STATUS_WORD = (RAM_BYTES - 16) / 4;
  localparam int GATE_WORD = (RAM_BYTES - 12) / 4;
  localparam int CHECKSUM_WORD = (RAM_BYTES - 8) / 4;
  localparam int RESULT_WORD = (RAM_BYTES - 4096) / 4;
  logic clk = 0, reset = 1;
  // Preemptive workload: raise the machine timer interrupt after `preempt`
  // cycles of task execution (scheduler time excluded); clear it once the core
  // takes the trap, as a timer tick handler would.
  logic timer_irq = 0;
  int unsigned preempt = 0, slice_cycles = 0;
  always #5 clk = ~clk;

  wallypipelinedcore #(P) core (
    .clk, .reset, .MTimerInt(timer_irq), .MExtInt(1'b0), .SExtInt(1'b0),
    .MSwInt(1'b0), .MTIME_CLINT(64'b0), .HRDATA(32'b0),
    .HREADY(1'b1), .HRESP(1'b0), .ExternalStall(1'b0),
    .HCLK(), .HRESETn(), .HADDR(), .HWDATA(), .HWSTRB(), .HWRITE(),
    .HSIZE(), .HBURST(), .HPROT(), .HTRANS(), .HMASTLOCK()
  );

  `define RAM core.lsu.dtim.dtim.ram.ram.RAM
  `define ROM core.ifu.irom.irom.rom.ROM
  `define CTXM observed_context_m
  `define CTXW core.priv.priv.csr.csrm.BPContextW

  // Observer metadata follows the same pipeline enables as the predictor.
  logic [P.BPRED_TASK_BITS:0] observed_context_f, observed_context_d, observed_context_e, observed_context_m;
  flopenr #(CONTEXT_WIDTH) context_f(clk, reset, ~core.StallF, core.BPContextF, observed_context_f);
  flopenrc #(CONTEXT_WIDTH) context_d(clk, reset, core.FlushD, ~core.StallD, observed_context_f, observed_context_d);
  flopenrc #(CONTEXT_WIDTH) context_e(clk, reset, core.FlushE, ~core.StallE, observed_context_d, observed_context_e);
  flopenrc #(CONTEXT_WIDTH) context_m(clk, reset, core.FlushM, ~core.StallM, observed_context_e, observed_context_m);

  string memfile, tracefile;
  int unsigned mode = 0, quantum = 16, workload = 0, iterations = 1024;
  longint unsigned maxcycles = 10000000, elapsed = 0;
  longint unsigned cycles = 0, instructions = 0, branches = 0, mispredictions = 0;
  longint unsigned hot_branches = 0, hot_mispredictions = 0;
  longint unsigned full_control_mispredictions = 0, hot_control_mispredictions = 0;
  longint unsigned target_mispredictions = 0, hot_target_mispredictions = 0;
  longint unsigned post_switch_branches = 0, post_switch_mispredictions = 0;
  longint unsigned task_branches[CONTEXTS] = '{default: 0}, task_misses[CONTEXTS] = '{default: 0};
  longint unsigned task_hot_branches[CONTEXTS] = '{default: 0}, task_hot_misses[CONTEXTS] = '{default: 0};
  longint unsigned task_window_branches[CONTEXTS] = '{default: 0}, task_window_misses[CONTEXTS] = '{default: 0};
  longint unsigned switches = 0;
  logic [31:0] hot_start = 0, hot_end = 0, hot_base = 0, hot_stride = 0;
  int unsigned window = 32, window_remaining = 0;
  bit measuring = 0, ever_measured = 0;
  logic [P.BPRED_TASK_BITS-1:0] previous_task = 0;
  bit valid, is_hot;
  int unsigned task_id;

  initial begin
    if (!$value$plusargs("mem=%s", memfile)) $fatal(1, "Required +mem=wordhex-file missing");
    void'($value$plusargs("mode=%d", mode));
    void'($value$plusargs("quantum=%d", quantum));
    void'($value$plusargs("workload=%d", workload));
    void'($value$plusargs("iterations=%d", iterations));
    void'($value$plusargs("maxcycles=%d", maxcycles));
    void'($value$plusargs("window=%d", window));
    void'($value$plusargs("preempt=%d", preempt));
    void'($value$plusargs("hot_start=%h", hot_start));
    void'($value$plusargs("hot_end=%h", hot_end));
    void'($value$plusargs("hot_base=%h", hot_base));
    void'($value$plusargs("hot_stride=%h", hot_stride));
    if (workload == 4 && preempt == 0) $fatal(1, "workload 4 requires +preempt=cycles");
    if (mode > 1 || quantum == 0 || iterations == 0)
      $fatal(1, "mode must be 0/1; quantum and iterations must be positive");
    if ($value$plusargs("trace=%s", tracefile)) begin
      $dumpfile(tracefile);
      $dumpvars(0, task_bpred_tb);
    end
    // Delay beyond the core ROM's built-in initialization before loading software.
    #1;
    for (int i = 0; i < $size(`ROM); i++) `ROM[i] = 32'h00000013;
    for (int i = 0; i < $size(`RAM); i++) `RAM[i] = 0;
    $readmemh(memfile, `ROM);
    $readmemh(memfile, `RAM);
    `RAM[ARG_WORD] = mode;
    `RAM[ARG_WORD+1] = quantum;
    `RAM[ARG_WORD+2] = workload;
    `RAM[ARG_WORD+3] = iterations;
    repeat (5) @(negedge clk);
    reset = 0;
  end

  // Match Wally's instruction-retirement qualification. Sampling before the
  // rising edge counts each accepted M-stage instruction once despite stalls.
  always @(posedge clk) begin
    if (!reset) begin
      elapsed++;
      if (elapsed > maxcycles)
        $fatal(1, "Watchdog: %0d cycles, PCM=%h status=%h cause=%h epc=%h", elapsed,
               core.PCM, `RAM[STATUS_WORD], `RAM[RESULT_WORD+4], `RAM[RESULT_WORD+5]);
      if (`RAM[GATE_WORD] != 0 && !measuring) begin
        measuring = 1;
        ever_measured = 1;
        previous_task = 0; // The first dispatch, to task 0, is not a switch.
        window_remaining = 0; // Cold start is not a context switch.
      end else if (`RAM[GATE_WORD] == 0) measuring = 0;
      if (core.TrapM) begin
        timer_irq <= 0;
        slice_cycles = 0;
      end else if (preempt != 0 && measuring &&
                   int'(`CTXW[P.BPRED_TASK_BITS-1:0]) != KERNEL_ID) begin
        if (slice_cycles + 1 >= preempt) timer_irq <= 1;
        else slice_cycles++;
      end
      if (measuring) begin
        cycles++;
        // Entering the scheduler is not a task switch; entering a different task is.
        if (int'(`CTXW[P.BPRED_TASK_BITS-1:0]) != KERNEL_ID &&
            `CTXW[P.BPRED_TASK_BITS-1:0] != previous_task) begin
          switches++;
          window_remaining = window;
          previous_task = `CTXW[P.BPRED_TASK_BITS-1:0];
        end
        valid = core.InstrValidM && !core.StallW && !core.FlushW;
        if (valid) begin
          instructions++;
          if (core.BPWrongM) full_control_mispredictions++;
          if (core.BTAWrongM) target_mispredictions++;
          if (core.InstrM[6:0] == 7'b1100011) begin
            task_id = int'(`CTXM[P.BPRED_TASK_BITS-1:0]);
            assert (task_id < CONTEXTS) else $fatal(1, "Invalid pipeline context ID %0d", task_id);
            branches++;
            task_branches[task_id]++;
            if (core.BPDirWrongM) begin
              mispredictions++;
              task_misses[task_id]++;
            end
            // Embench (workload 4) has no labeled branch: count every task branch.
            is_hot = workload == 4 ? (task_id != KERNEL_ID) :
                     workload == 3 ?
                     (hot_stride != 0 && core.PCM == hot_base + task_id * hot_stride) :
                     (core.PCM >= hot_start && core.PCM < hot_end);
            if (is_hot) begin
              hot_branches++;
              if (core.BPWrongM) hot_control_mispredictions++;
              if (core.BTAWrongM) hot_target_mispredictions++;
              task_hot_branches[task_id]++;
              if (core.BPDirWrongM) begin
                hot_mispredictions++;
                task_hot_misses[task_id]++;
              end
              if (window_remaining != 0) begin
                window_remaining--;
                post_switch_branches++;
                task_window_branches[task_id]++;
                if (core.BPDirWrongM) begin
                  post_switch_mispredictions++;
                  task_window_misses[task_id]++;
                end
              end
            end
          end
        end
      end
    end
  end

  // At the falling edge all synchronous memory writes have settled.
  always @(negedge clk) begin
    if (!reset && `RAM[STATUS_WORD] != 0) begin
      $write("RESULT {\"status\":%0d,\"mode\":%0d,\"quantum\":%0d,\"workload\":%0d,\"iterations\":%0d,",
             `RAM[STATUS_WORD], mode, quantum, workload, iterations);
      $write("\"predictor_entries\":%0d,\"btb_entries\":%0d,\"ras_entries\":%0d,\"window\":%0d,",
             2**P.BPRED_SIZE, 2**P.BTB_SIZE, P.RAS_SIZE, window);
      $write("\"tasks\":%0d,\"contexts\":%0d,\"banks\":%0d,\"entries_per_task\":%0d,\"ram_bytes\":%0d,",
             TASK_COUNT, CONTEXTS, BANKS, (2**P.BPRED_SIZE)/BANKS, RAM_BYTES);
      $write("\"predictor_type\":%0d,", P.BPRED_TYPE);
      $write("\"kernel_branches\":%0d,\"kernel_mispredictions\":%0d,",
             task_branches[KERNEL_ID], task_misses[KERNEL_ID]);
      $write("\"cycles\":%0d,\"instructions\":%0d,\"branches\":%0d,\"mispredictions\":%0d,\"switches\":%0d,",
             cycles, instructions, branches, mispredictions, switches);
      $write("\"hot_branches\":%0d,\"hot_mispredictions\":%0d,\"post_switch_branches\":%0d,\"post_switch_mispredictions\":%0d,",
             hot_branches, hot_mispredictions, post_switch_branches, post_switch_mispredictions);
      $write("\"full_control_mispredictions\":%0d,\"hot_control_mispredictions\":%0d,\"target_mispredictions\":%0d,\"hot_target_mispredictions\":%0d,",
             full_control_mispredictions, hot_control_mispredictions, target_mispredictions, hot_target_mispredictions);
      $write("\"checksum\":%0d,\"software_cycles\":%0d,\"software_instructions\":%0d,\"software_switches\":%0d,\"software_task_count\":%0d,",
             `RAM[CHECKSUM_WORD], `RAM[RESULT_WORD], `RAM[RESULT_WORD+1],
             `RAM[RESULT_WORD+2], `RAM[RESULT_WORD+3]);
      $write("\"trap_cause\":%0d,\"trap_epc\":%0d,\"trap_value\":%0d,\"per_task\":[",
             `RAM[RESULT_WORD+4], `RAM[RESULT_WORD+5], `RAM[RESULT_WORD+6]);
      for (int t = 0; t < TASK_COUNT; t++) begin
        if (t != 0) $write(",");
        $write("{\"task\":%0d,\"checksum\":%0d,\"expected\":%0d,\"completed\":%0d,",
               t, `RAM[RESULT_WORD+8+3*t], `RAM[RESULT_WORD+9+3*t], `RAM[RESULT_WORD+10+3*t]);
        $write("\"branches\":%0d,\"mispredictions\":%0d,\"hot_branches\":%0d,\"hot_mispredictions\":%0d,\"post_switch_branches\":%0d,\"post_switch_mispredictions\":%0d}",
               task_branches[t], task_misses[t], task_hot_branches[t], task_hot_misses[t], task_window_branches[t], task_window_misses[t]);
      end
      $display("]}");
      if (`RAM[STATUS_WORD] != 1) $fatal(1, "Software self-check failed");
      if (!ever_measured) $fatal(1, "Software completed without measurement gate");
      $finish;
    end
  end
endmodule
