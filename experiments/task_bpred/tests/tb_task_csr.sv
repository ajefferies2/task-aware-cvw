`timescale 1ns/1ps
`include "BranchPredictorType.vh"
// Exercise the real machine-CSR implementation independently of software.
module tb_task_csr import cvw::*; #(parameter TASKS = 2) (output logic done = 0);
  localparam TASK_BITS = (TASKS > 1) ? $clog2(TASKS) : 1;
  localparam cvw_t P = '{XLEN:32, PA_BITS:34, BPRED_TASKS:TASKS,
    BPRED_TASK_BITS:TASK_BITS, BPRED_SUPPORTED:1'b1,
    BPRED_TYPE:`BP_TASK_TWOBIT, default:'0};
  logic clk = 0, reset = 1, CSRMWriteM = 0;
  logic [11:0] CSRAdrM = 12'hBC0;
  logic [31:0] CSRWriteValM = 0, CSRMReadValM;
  logic [TASK_BITS:0] BPContextF;
  logic IllegalCSRMAccessM;
  always #5 clk = ~clk;
  csrm #(P) dut(.clk, .reset, .CSRMWriteM, .UngatedCSRMWriteM(CSRMWriteM),
    .MTrapM(1'b0), .CSRAdrM, .NextEPCM('0), .NextXtvalM('0), .MSTATUS_REGW('0),
    .MSTATUSH_REGW('0), .NextCauseM('0), .CSRWriteValM, .MIP_REGW('0), .MIE_REGW('0),
    .CSRMReadValM, .BPContextF, .IllegalCSRMAccessM, .MTVEC_REGW(), .MEPC_REGW(),
    .MCOUNTEREN_REGW(), .MCOUNTINHIBIT_REGW(), .MEDELEG_REGW(), .MIDELEG_REGW(),
    .PMPADDR_ARRAY_REGW(), .PMPCFG_ARRAY_REGW(), .WriteMSTATUSM(), .WriteMSTATUSHM(),
    .IllegalCSRMWriteReadonlyM(), .MENVCFG_REGW());

  task automatic write_check(input logic [31:0] raw_value, expected);
    logic [TASK_BITS:0] expected_context;
    expected_context = {expected[8], TASK_BITS'(expected[7:0])};
    CSRWriteValM = raw_value; CSRMWriteM = 1;
    #1;
    if (BPContextF !== expected_context)
      $fatal(1, "CSR tasks=%0d incorrect forwarded context for %h", TASKS, raw_value);
    @(posedge clk); #1; CSRMWriteM = 0; #1;
    if (CSRMReadValM !== expected || BPContextF !== expected_context || IllegalCSRMAccessM)
      $fatal(1, "CSR tasks=%0d write=%h read=%h expected=%h", TASKS, raw_value, CSRMReadValM, expected);
  endtask

  initial begin
    @(posedge clk); #1; reset = 0; #1;
    if (CSRMReadValM !== 0 || BPContextF !== 0) $fatal(1, "CSR reset must select shared task zero");
    // Probe all 256 software ID encodings, including IDs that would alias if
    // the implementation truncated before range checking. Reserved bits clear.
    for (int raw_id = 0; raw_id < 256; raw_id++) begin
      write_check(32'hFFFF_FF00 | raw_id, 32'h100 | ((raw_id < TASKS) ? raw_id : 0));
      write_check(32'hFFFF_FE00 | raw_id, (raw_id < TASKS) ? raw_id : 0);
    end
    // A gated-off write must neither forward nor alter the stored context.
    write_check(0, 0);
    CSRWriteValM = 32'h101; #1;
    if (BPContextF !== 0) $fatal(1, "gated CSR write incorrectly forwarded context");
    @(posedge clk); #1;
    if (CSRMReadValM !== 0) $fatal(1, "gated CSR write changed context");
    done = 1;
  end
endmodule
