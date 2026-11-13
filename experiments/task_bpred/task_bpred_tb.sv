// SPDX-License-Identifier: Apache-2.0
// Small deterministic simulation environment for the actual Wally pipeline.
`include "config.vh"
import cvw::*;

module task_bpred_tb;
  `include "parameter-defs.vh"
  logic clk = 0, reset = 1;
  always #5 clk = ~clk;

  wallypipelinedcore #(P) core (
    .clk, .reset, .MTimerInt(1'b0), .MExtInt(1'b0), .SExtInt(1'b0),
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
  logic [1:0] observed_context_f, observed_context_d, observed_context_e, observed_context_m;
  flopenr #(2) context_f(clk, reset, ~core.StallF, core.BPContextF, observed_context_f);
  flopenrc #(2) context_d(clk, reset, core.FlushD, ~core.StallD, observed_context_f, observed_context_d);
  flopenrc #(2) context_e(clk, reset, core.FlushE, ~core.StallE, observed_context_d, observed_context_e);
  flopenrc #(2) context_m(clk, reset, core.FlushM, ~core.StallM, observed_context_e, observed_context_m);

  string memfile, tracefile;
  int unsigned mode = 0, quantum = 16, workload = 0, iterations = 1024;
  longint unsigned maxcycles = 10000000, elapsed = 0;
  longint unsigned cycles = 0, instructions = 0, branches = 0, mispredictions = 0;
  longint unsigned hot_branches = 0, hot_mispredictions = 0;
  longint unsigned full_control_mispredictions = 0, hot_control_mispredictions = 0;
  longint unsigned target_mispredictions = 0, hot_target_mispredictions = 0;
  longint unsigned post_switch_branches = 0, post_switch_mispredictions = 0;
  longint unsigned task_branches[2] = '{0, 0}, task_misses[2] = '{0, 0};
  longint unsigned task_hot_branches[2] = '{0, 0}, task_hot_misses[2] = '{0, 0};
  longint unsigned task_window_branches[2] = '{0, 0}, task_window_misses[2] = '{0, 0};
  longint unsigned switches = 0;
  logic [31:0] hot0_start = 0, hot0_end = 0, hot1_start = 0, hot1_end = 0;
  int unsigned window = 32, window_remaining = 0;
  bit measuring = 0, ever_measured = 0, previous_task = 0;
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
    void'($value$plusargs("hot0_start=%h", hot0_start));
    void'($value$plusargs("hot0_end=%h", hot0_end));
    void'($value$plusargs("hot1_start=%h", hot1_start));
    void'($value$plusargs("hot1_end=%h", hot1_end));
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
    `RAM['hffe0 / 4] = mode;
    `RAM['hffe4 / 4] = quantum;
    `RAM['hffe8 / 4] = workload;
    `RAM['hffec / 4] = iterations;
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
               core.PCM, `RAM['hfff0 / 4], `RAM['hffc4 / 4], `RAM['hffc8 / 4]);
      if (`RAM['hfff4 / 4] != 0 && !measuring) begin
        measuring = 1;
        ever_measured = 1;
        previous_task = `CTXW[0];
        window_remaining = 0; // Cold start is not a context switch.
      end else if (`RAM['hfff4 / 4] == 0) measuring = 0;
      if (measuring) begin
        cycles++;
        if (`CTXW[0] != previous_task) begin
          switches++;
          window_remaining = window;
          previous_task = `CTXW[0];
        end
        valid = core.InstrValidM && !core.StallW && !core.FlushW;
        if (valid) begin
          instructions++;
          if (core.BPWrongM) full_control_mispredictions++;
          if (core.BTAWrongM) target_mispredictions++;
          if (core.InstrM[6:0] == 7'b1100011) begin
            task_id = int'(`CTXM[0]);
            branches++;
            task_branches[task_id]++;
            if (core.BPDirWrongM) begin
              mispredictions++;
              task_misses[task_id]++;
            end
            is_hot = (core.PCM >= hot0_start && core.PCM < hot0_end) ||
                     (core.PCM >= hot1_start && core.PCM < hot1_end);
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
    if (!reset && `RAM['hfff0 / 4] != 0) begin
      $write("RESULT {\"status\":%0d,\"mode\":%0d,\"quantum\":%0d,\"workload\":%0d,\"iterations\":%0d,",
             `RAM['hfff0 / 4], mode, quantum, workload, iterations);
      $write("\"predictor_entries\":%0d,\"btb_entries\":%0d,\"ras_entries\":%0d,\"window\":%0d,",
             2**P.BPRED_SIZE, 2**P.BTB_SIZE, P.RAS_SIZE, window);
      $write("\"cycles\":%0d,\"instructions\":%0d,\"branches\":%0d,\"mispredictions\":%0d,\"switches\":%0d,",
             cycles, instructions, branches, mispredictions, switches);
      $write("\"hot_branches\":%0d,\"hot_mispredictions\":%0d,\"post_switch_branches\":%0d,\"post_switch_mispredictions\":%0d,",
             hot_branches, hot_mispredictions, post_switch_branches, post_switch_mispredictions);
      $write("\"full_control_mispredictions\":%0d,\"hot_control_mispredictions\":%0d,\"target_mispredictions\":%0d,\"hot_target_mispredictions\":%0d,",
             full_control_mispredictions, hot_control_mispredictions, target_mispredictions, hot_target_mispredictions);
      $write("\"checksum\":%0d,\"checksum0\":%0d,\"checksum1\":%0d,\"software_cycles\":%0d,\"software_instructions\":%0d,\"software_switches\":%0d,",
             `RAM['hfff8 / 4], `RAM['hffb0 / 4], `RAM['hffb4 / 4], `RAM['hffb8 / 4], `RAM['hffbc / 4], `RAM['hffc0 / 4]);
      $write("\"trap_cause\":%0d,\"trap_epc\":%0d,\"trap_value\":%0d,\"per_task\":[",
             `RAM['hffc4 / 4], `RAM['hffc8 / 4], `RAM['hffcc / 4]);
      for (int t = 0; t < 2; t++) begin
        if (t != 0) $write(",");
        $write("{\"task\":%0d,\"branches\":%0d,\"mispredictions\":%0d,\"hot_branches\":%0d,\"hot_mispredictions\":%0d,\"post_switch_branches\":%0d,\"post_switch_mispredictions\":%0d}",
               t, task_branches[t], task_misses[t], task_hot_branches[t], task_hot_misses[t], task_window_branches[t], task_window_misses[t]);
      end
      $display("]}");
      if (`RAM['hfff0 / 4] != 1) $fatal(1, "Software self-check failed");
      if (!ever_measured) $fatal(1, "Software completed without measurement gate");
      $finish;
    end
  end
endmodule
