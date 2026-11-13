`timescale 1ns/1ps
module tb_task_predictor #(parameter TASKS = 2);
  localparam TASK_BITS = (TASKS > 1) ? $clog2(TASKS) : 1;
  localparam BANK_BITS = (TASKS > 1) ? $clog2(TASKS) : 0;
  localparam ENTRIES_PER_BANK = 256 >> BANK_BITS;
  typedef logic [TASK_BITS:0] context_t;
  logic clk = 0, reset = 0;
  logic StallF = 0, StallD = 0, StallE = 0, StallM = 0, StallW = 0;
  logic FlushD = 0, FlushE = 0, FlushM = 0, FlushW = 0;
  logic [31:0] PCNextF = 32'h80000000;
  context_t BPContextF = '0;
  logic [1:0] BPDirF;
  logic BranchE = 0, BranchM = 0, PCSrcE = 0, BPDirWrongE;
  logic csr_done;
  taskTwoBitPredictor #(32, 8, TASKS) dut(.*);
  tb_task_csr #(TASKS) csr_checks(.done(csr_done));
  always #5 clk = ~clk;

  function automatic context_t context_value(input bit partitioned, input int task_id);
    return context_t'((int'(partitioned) << TASK_BITS) | task_id);
  endfunction
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
  task automatic lookup(input context_t ctx, input logic [31:0] pc);
    BPContextF = ctx; PCNextF = pc; tick();
  endtask
  task automatic train(input context_t ctx, input logic taken);
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
               ctx[TASK_BITS] ? "partitioned" : "shared     ", ctx[TASK_BITS-1:0],
               taken ? "T " : "NT", before_state, BPDirF);
  endtask
  task automatic check_counter(input logic [1:0] expected, input string label_text);
    if (BPDirF !== expected)
      $fatal(1, "%s (tasks=%0d): got %b, expected %b", label_text, TASKS, BPDirF, expected);
  endtask

  initial begin
    restart(); lookup(context_value(0, 0), 32'h80000000);
    check_counter(2'b01, "deterministic weak-not-taken reset");
    for (int i = 0; i < 5; i++) train(context_value(1, 0), 1);
    check_counter(2'b11, "taken saturation");
    for (int i = 0; i < 5; i++) train(context_value(1, TASKS-1), 0);
    check_counter(2'b00, "not-taken saturation");
    if (TASKS > 1) begin
      lookup(context_value(1, 0), 32'h80000000);
      check_counter(2'b11, "partition preserves task zero after last task trains");
    end

    restart();
    for (int i = 0; i < 3; i++) train(context_value(0, 0), 1);
    for (int i = 0; i < 3; i++) train(context_value(0, TASKS-1), 0);
    lookup(context_value(0, 0), 32'h80000000);
    check_counter(2'b00, "shared mode updates same PC slot across all tasks");

    // The first address in the next bank is distinct in shared mode and
    // aliases in task-zero's partition. TASKS=1 retains the entire table.
    restart(); train(context_value(0, 0), 1);
    if (TASKS > 1) begin
      lookup(context_value(0, 0), 32'h80000000 + (ENTRIES_PER_BANK << 2));
      check_counter(2'b01, "shared PC index retains bank-select bits");
      lookup(context_value(1, 0), 32'h80000000 + (ENTRIES_PER_BANK << 2));
      check_counter(2'b10, "partition aliases bank-select PC bits at equal capacity");
    end else begin
      lookup(context_value(1, 0), 32'h80000200);
      check_counter(2'b01, "one-task partition retains all 256 PC slots");
      lookup(context_value(1, 0), 32'h80000000);
      check_counter(2'b10, "one-task partition uses shared table state");
    end

    // Every declared task must select an independent bank, including IDs
    // above one and the highest usable ID for non-power-of-two counts.
    restart();
    for (int t = 0; t < TASKS; t++) begin
      for (int i = 0; i < 3; i++) train(context_value(1, t), (t % 2) == 0);
      // Checking still-untrained banks catches aliases even when two tasks
      // have identical training outcomes (for example IDs zero and two).
      for (int other = t + 1; other < TASKS; other++) begin
        lookup(context_value(1, other), 32'h80000000);
        check_counter(2'b01, "training one task leaves every untouched bank cold");
      end
    end
    for (int t = 0; t < TASKS; t++) begin
      lookup(context_value(1, t), 32'h80000000);
      check_counter((t % 2) == 0 ? 2'b11 : 2'b00, "independent per-task bank");
    end
    if (TASKS < (1 << BANK_BITS)) begin
      for (int i = TASKS * ENTRIES_PER_BANK; i < 256; i++)
        if (dut.Counters[i] !== 2'b01) $fatal(1, "unused padded bank was modified");
    end

    if (TASKS > 1) begin
      // Change to task zero while a highest-ID branch is in flight. Its
      // update must use the original captured index, not the current CSR ID.
      restart(); lookup(context_value(1, TASKS-1), 32'h80000000); tick(); tick();
      BranchE = 1; PCSrcE = 1; BPContextF = context_value(1, 0);
      tick(); BranchE = 0; BranchM = 1; tick(); BranchM = 0;
      lookup(context_value(1, 0), 32'h80000000);
      check_counter(2'b01, "in-flight old task branch did not train new task");
      lookup(context_value(1, TASKS-1), 32'h80000000);
      check_counter(2'b10, "in-flight old task branch trained its original slot");
    end

    // Back-to-back alias updates must use the current counter state.
    restart(); lookup(context_value(0, 0), 32'h80000000); tick(); tick();
    BranchE = 1; PCSrcE = 1;
    #1; if (!BPDirWrongE) $fatal(1, "cold taken branch must report direction miss");
    tick(); BranchM = 1;
    tick(); tick(); BranchE = 0; BranchM = 0;
    check_counter(2'b11, "adjacent aliasing branches accumulate updates");
    tick(); tick(); BranchE = 1; PCSrcE = 1;
    #1; if (BPDirWrongE) $fatal(1, "trained taken branch must predict correctly");
    BranchE = 0;

    restart(); lookup(context_value(0, 0), 32'h80000000); tick(); tick();
    BranchE = 1; PCSrcE = 1; tick(); BranchE = 0; BranchM = 1;
    {StallF, StallD, StallE, StallM, StallW} = '1;
    repeat (4) tick();
    check_counter(2'b01, "stalled branch does not repeatedly train");
    {StallF, StallD, StallE, StallM, StallW} = '0;
    tick(); BranchM = 0;
    check_counter(2'b10, "stalled branch trains exactly once when released");

    restart(); lookup(context_value(0, 0), 32'h80000000); tick(); tick();
    BranchE = 1; PCSrcE = 1; tick(); BranchE = 0; BranchM = 1;
    FlushW = 1; tick(); BranchM = 0; FlushW = 0;
    check_counter(2'b01, "flushed branch cannot train");
    wait (csr_done);
    $display("PASS: tasks=%0d predictor reset, saturation, equal capacity, interference, banks, ownership, aliasing, stall, flush; CSR validation/forwarding", TASKS);
    $finish;
  end
endmodule
