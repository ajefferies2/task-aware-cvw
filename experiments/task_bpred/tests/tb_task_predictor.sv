`timescale 1ns/1ps
module tb_task_predictor;
  logic clk = 0, reset = 0;
  logic StallF = 0, StallD = 0, StallE = 0, StallM = 0, StallW = 0;
  logic FlushD = 0, FlushE = 0, FlushM = 0, FlushW = 0;
  logic [31:0] PCNextF = 32'h80000000;
  logic [1:0] BPContextF = 0, BPDirF;
  logic BranchE = 0, BranchM = 0, PCSrcE = 0, BPDirWrongE;
  taskTwoBitPredictor #(32, 8) dut(.*);
  always #5 clk = ~clk;

  task automatic tick;
    @(posedge clk); #1;
  endtask
  task automatic restart;
    reset = 1;
    BranchE = 0; BranchM = 0;
    {StallF, StallD, StallE, StallM, StallW} = '0;
    {FlushD, FlushE, FlushM, FlushW} = '0;
    tick(); reset = 0;
    if ($test$plusargs("show_counters")) $display("RESET: all counters = 01");
  endtask
  task automatic lookup(input logic [1:0] ctx, input logic [31:0] pc);
    BPContextF = ctx; PCNextF = pc; tick();
  endtask
  task automatic train(input logic [1:0] ctx, input logic taken);
    logic [1:0] before_state;
    lookup(ctx, 32'h80000000);
    before_state = BPDirF;
    tick(); tick(); // F -> D -> E
    BranchE = 1; PCSrcE = taken;
    tick(); // E -> M
    BranchE = 0; BranchM = 1;
    tick(); // M update
    BranchM = 0;
    if ($test$plusargs("show_counters"))
      $display("COUNTER mode=%s task=%0d outcome=%s state=%02b -> %02b",
               ctx[1] ? "partitioned" : "shared     ", ctx[0],
               taken ? "T " : "NT", before_state, BPDirF);
  endtask
  task automatic check_counter(input logic [1:0] expected, input string label_text);
    if (BPDirF !== expected)
      $fatal(1, "%s: got %b, expected %b", label_text, BPDirF, expected);
  endtask

  initial begin
    restart(); lookup(2'b00, 32'h80000000);
    check_counter(2'b01, "deterministic weak-not-taken reset");
    for (int i = 0; i < 5; i++) train(2'b10, 1);
    check_counter(2'b11, "taken saturation");
    for (int i = 0; i < 5; i++) train(2'b11, 0);
    check_counter(2'b00, "not-taken saturation");
    lookup(2'b10, 32'h80000000);
    check_counter(2'b11, "partition preserves task zero after task one trains");

    restart();
    for (int i = 0; i < 3; i++) train(2'b00, 1);
    for (int i = 0; i < 3; i++) train(2'b01, 0);
    lookup(2'b00, 32'h80000000);
    check_counter(2'b00, "shared mode permits cross-task interference");

    // Shared mode has 256 PC slots; partitioned mode has 128 per task.
    restart(); train(2'b00, 1);
    lookup(2'b00, 32'h80000200);
    check_counter(2'b01, "shared high PC index bit selects separate slot");
    lookup(2'b10, 32'h80000200);
    check_counter(2'b10, "partition drops high PC index bit at equal capacity");

    // A task switch while a branch is in flight cannot redirect its update.
    restart(); lookup(2'b10, 32'h80000000); tick(); tick();
    BranchE = 1; PCSrcE = 1; BPContextF = 2'b11;
    tick(); BranchE = 0; BranchM = 1; tick(); BranchM = 0;
    lookup(2'b11, 32'h80000000);
    check_counter(2'b01, "in-flight old task branch did not train new task");
    lookup(2'b10, 32'h80000000);
    check_counter(2'b10, "in-flight old task branch trained its original slot");

    // Back-to-back alias updates must use the current counter state.
    restart(); lookup(2'b00, 32'h80000000); tick(); tick();
    BranchE = 1; PCSrcE = 1; tick(); BranchM = 1;
    tick(); tick(); BranchE = 0; BranchM = 0;
    check_counter(2'b11, "adjacent aliasing branches accumulate updates");

    restart(); lookup(2'b00, 32'h80000000); tick(); tick();
    BranchE = 1; PCSrcE = 1; tick(); BranchE = 0; BranchM = 1;
    {StallF, StallD, StallE, StallM, StallW} = '1;
    repeat (4) tick();
    check_counter(2'b01, "stalled branch does not repeatedly train");
    {StallF, StallD, StallE, StallM, StallW} = '0;
    tick(); BranchM = 0;
    check_counter(2'b10, "stalled branch trains exactly once when released");

    restart(); lookup(2'b00, 32'h80000000); tick(); tick();
    BranchE = 1; PCSrcE = 1; tick(); BranchE = 0; BranchM = 1;
    FlushW = 1; tick(); BranchM = 0; FlushW = 0;
    check_counter(2'b01, "flushed branch cannot train");
    $display("PASS: task predictor reset, saturation, equal capacity, interference, ownership, aliasing, stall, flush");
    $finish;
  end
endmodule
