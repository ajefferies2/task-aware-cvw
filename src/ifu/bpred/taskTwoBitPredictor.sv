// Task-indexed two-bit direction predictor for the CPE5300 experiment.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Both modes have exactly 2**k counters. Partitioned mode reserves half for
// each of two tasks; shared mode uses all PC index bits. BTB/RAS are unchanged.
module taskTwoBitPredictor #(parameter XLEN = 32, parameter k = 8) (
  input  logic clk, reset,
  input  logic StallF, StallD, StallE, StallM, StallW,
  input  logic FlushD, FlushE, FlushM, FlushW,
  input  logic [XLEN-1:0] PCNextF,
  input  logic [1:0] BPContextF, // bit 1: partition, bit 0: task
  input  logic BranchE, BranchM, PCSrcE,
  output logic [1:0] BPDirF,
  output logic BPDirWrongE
);
  localparam ENTRIES = 2**k;
  logic [1:0] Counters [ENTRIES-1:0];
  logic [k-1:0] PCIndexNextF, IndexNextF, IndexF, IndexD, IndexE, IndexM;
  logic [1:0] ContextF, ContextD, ContextE, ContextM;
  logic [1:0] BPDirD, BPDirE, UpdatedCounterM;
  logic PCSrcM, TrainM;

  initial begin
    assert (k >= 2 && k + 1 < XLEN)
      else $fatal(1, "taskTwoBitPredictor requires 2 <= k < XLEN-1");
  end

  // Fold bit 1 into the top PC bit to retain compressed-instruction support.
  assign PCIndexNextF = {PCNextF[k+1] ^ PCNextF[1], PCNextF[k:2]};
  assign IndexNextF = BPContextF[1] ? {BPContextF[0], PCIndexNextF[k-2:0]} : PCIndexNextF;
  flopenr #(k) indexregF(clk, reset, ~StallF, IndexNextF, IndexF);
  flopenr #(2) contextregF(clk, reset, ~StallF, BPContextF, ContextF);
  assign BPDirF = Counters[IndexF];

  // Carry the actual lookup index, rather than re-indexing with the current
  // task at resolution. Flush/stall behavior matches the instruction pipeline.
  flopenrc #(k) indexregD(clk, reset, FlushD, ~StallD, IndexF, IndexD);
  flopenrc #(k) indexregE(clk, reset, FlushE, ~StallE, IndexD, IndexE);
  flopenrc #(k) indexregM(clk, reset, FlushM, ~StallM, IndexE, IndexM);
  flopenrc #(2) contextregD(clk, reset, FlushD, ~StallD, ContextF, ContextD);
  flopenrc #(2) contextregE(clk, reset, FlushE, ~StallE, ContextD, ContextE);
  flopenrc #(2) contextregM(clk, reset, FlushM, ~StallM, ContextE, ContextM);
  flopenrc #(2) predictionregD(clk, reset, FlushD, ~StallD, BPDirF, BPDirD);
  flopenrc #(2) predictionregE(clk, reset, FlushE, ~StallE, BPDirD, BPDirE);
  flopenrc #(1) outcomeregM(clk, reset, FlushM, ~StallM, PCSrcE, PCSrcM);
  assign BPDirWrongE = BranchE & (PCSrcE != BPDirE[1]);

  // Train once when the branch leaves M. Read the current table state here,
  // so adjacent aliasing branches cannot overwrite each other's updates with
  // a counter value captured several cycles earlier at prediction time.
  assign TrainM = BranchM & ~StallW & ~FlushW;
  always_comb begin
    UpdatedCounterM = Counters[IndexM];
    if (PCSrcM && Counters[IndexM] != 2'b11)
      UpdatedCounterM = Counters[IndexM] + 2'b01;
    else if (!PCSrcM && Counters[IndexM] != 2'b00)
      UpdatedCounterM = Counters[IndexM] - 2'b01;
  end
  always_ff @(posedge clk) begin
    if (reset) begin
      for (int i = 0; i < ENTRIES; i++) Counters[i] <= 2'b01;
    end else if (TrainM) Counters[IndexM] <= UpdatedCounterM;
  end
endmodule
