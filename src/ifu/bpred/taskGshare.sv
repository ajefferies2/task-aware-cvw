// Task-aware gshare direction predictor for the CPE5300 experiment.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Derived from Wally's gshare.sv (Rose Thompson, Shreya Sanghai). With the
// task-aware mode bit clear it is exactly gshare: one global history register
// and one pattern history table (PHT). With the bit set, every context keeps
// its own committed global history, so one task's branches never shift another
// task's history. The PHT stays shared in both modes.
//
// A context CSR write flushes all younger instructions, and every older branch
// has committed its history by the time the write reaches M, so all in-flight
// branches belong to the current context, which therefore selects the history.
module taskGshare import cvw::*; #(
  parameter cvw_t P, parameter XLEN = 32, parameter k = 10, parameter TASKS = 2,
  localparam TASK_BITS = (TASKS > 1) ? $clog2(TASKS) : 1
) (
  input  logic             clk, reset,
  input  logic             StallF, StallD, StallE, StallM, StallW,
  input  logic             FlushD, FlushE, FlushM, FlushW,
  input  logic [TASK_BITS:0] BPContextF, // top bit: task-aware mode, lower bits: context
  output logic [1:0]       BPDirF,
  output logic             BPDirWrongE,
  input  logic [XLEN-1:0]  PCNextF, PCF, PCD, PCE, PCM,
  input  logic             BPBranchF, BranchD, BranchE, BranchM, BranchW, PCSrcE
);
  logic                   MatchD, MatchE, MatchM, MatchW, MatchX;
  logic [1:0]             PHTBPDirF, BPDirD, BPDirE, FwdNewBPDirF;
  logic [1:0]             NewBPDirE, NewBPDirM, NewBPDirW;
  logic [k-1:0]           IndexNextF, IndexF, IndexD, IndexE, IndexM, IndexW;
  logic [k-1:0]           GHRF, GHRD, GHRE, GHRM, GHRNextM, GHRNextF;
  logic [k-1:0]           GHR [TASKS-1:0];
  logic                   PCSrcM;
  logic [TASK_BITS-1:0]   HistorySel;

  // Task-aware mode selects the current context's history; otherwise all share GHR[0].
  assign HistorySel = BPContextF[TASK_BITS] ? BPContextF[TASK_BITS-1:0] : '0;

  assign IndexNextF = GHRNextF ^ {PCNextF[k+1] ^ PCNextF[1], PCNextF[k:2]};
  assign IndexF     = GHRF ^ {PCF[k+1] ^ PCF[1], PCF[k:2]};
  assign IndexD     = GHRD ^ {PCD[k+1] ^ PCD[1], PCD[k:2]};
  assign IndexE     = GHRE ^ {PCE[k+1] ^ PCE[1], PCE[k:2]};
  assign IndexM     = GHRM ^ {PCM[k+1] ^ PCM[1], PCM[k:2]};

  flopenrc #(k) IndexWReg(clk, reset, FlushW, ~StallW, IndexM, IndexW);

  // Forward updates of in-flight branches that use the same PHT entry.
  assign MatchD = BranchD & ~FlushE & (IndexF == IndexD);
  assign MatchE = BranchE & ~FlushM & (IndexF == IndexE);
  assign MatchM = BranchM & ~FlushW & (IndexF == IndexM);
  assign MatchW = BranchW & ~FlushW & (IndexF == IndexW);
  assign MatchX = MatchD | MatchE | MatchM | MatchW;

  assign FwdNewBPDirF = MatchD ? {2{BPDirD[1]}} :
                        MatchE ? NewBPDirE :
                        MatchM ? NewBPDirM :
                                 NewBPDirW;
  assign BPDirF = MatchX ? FwdNewBPDirF : PHTBPDirF;

  ram2p1r1wbe #(.USE_SRAM(P.USE_SRAM), .DEPTH(2**k), .WIDTH(2)) PHT(.clk(clk),
    .ce1(~StallF), .ce2(~StallW & ~FlushW),
    .ra1(IndexNextF), .rd1(PHTBPDirF),
    .wa2(IndexM), .wd2(NewBPDirM), .we2(BranchM), .bwe2(1'b1));

  flopenrc #(2) PredictionRegD(clk, reset, FlushD, ~StallD, BPDirF, BPDirD);
  flopenrc #(2) PredictionRegE(clk, reset, FlushE, ~StallE, BPDirD, BPDirE);

  satCounter2 BPDirUpdateE(.BrDir(PCSrcE), .OldState(BPDirE), .NewState(NewBPDirE));
  flopenrc #(2) NewPredictionRegM(clk, reset, FlushM, ~StallM, NewBPDirE, NewBPDirM);
  flopenrc #(2) NewPredictionRegW(clk, reset, FlushW, ~StallW, NewBPDirM, NewBPDirW);

  assign BPDirWrongE = PCSrcE != BPDirE[1] & BranchE;

  // Speculative history: the current context's committed history, plus the
  // outcomes or predictions of younger in-flight branches.
  assign GHRM     = GHR[HistorySel];
  assign GHRNextF = BPBranchF ? {BPDirF[1], GHRF[k-1:1]} : GHRF;
  assign GHRF     = BranchD ? {BPDirD[1], GHRD[k-1:1]} : GHRD;
  assign GHRD     = BranchE ? {PCSrcE, GHRE[k-1:1]} : GHRE;
  assign GHRE     = BranchM ? {PCSrcM, GHRM[k-1:1]} : GHRM;
  assign GHRNextM = {PCSrcM, GHRM[k-1:1]};

  always_ff @(posedge clk)
    if (reset) for (int i = 0; i < TASKS; i++) GHR[i] <= '0;
    else if (~StallW & ~FlushW & BranchM) GHR[HistorySel] <= GHRNextM;

  flopenrc #(1) PCSrcMReg(clk, reset, FlushM, ~StallM, PCSrcE, PCSrcM);
endmodule
