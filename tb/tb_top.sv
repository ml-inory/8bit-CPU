`timescale 1ns / 1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Testbench for the 8-bit CPU (rtl/top.sv)
//
// ROM contents are a compile-time parameter, so four independent DUTs run four
// programs in parallel off one clock. Every DUT is driven only through its
// top-level ports (clk, rst) and observed only through top-level outputs
// (`out`, and `rom_addr`/`rom_data` to detect HLT). Expected values are derived
// from ISA.txt -- never from the RTL internals. Internals are read only to make
// a failing check readable.
//
// Each DUT has a tb_tap alongside it. `top.out` is combinational (`out` is A
// only while the OUT instruction is on the ROM bus) and it depends on the
// accumulator, which the rising edge updates. The tap therefore samples on the
// falling edge, where registers and combinational logic have settled and the
// instruction is still on the bus, and presents the result on the next falling
// edge for the testbench to collect.
//
// All four programs are expected to PASS:
//   A  basic store / load-back / output
//   B  ADD and SUB
//   C  load with a gap after the store
//   D  load immediately after the store, with no gap, and a load as the very
//      first instruction -- these are the regression guards
//
// C and D historically failed. MEM.rdata used to be a registered output, so a
// load-type opcode consumed the previous cycle's data; D (and a gap-less load)
// then read a stale value. The RTL now reads MEM combinationally, and all four
// programs pass.
//
// Self-checking: every check prints PASS or FAIL, and a non-zero $fatal ends
// the run if any check failed.
//
//   +trace   print a cycle-by-cycle trace of DUT B
// -----------------------------------------------------------------------------

module tb_top;

    localparam int DATA_WIDTH     = 8;
    localparam int MEM_ADDR_WIDTH = 4;
    localparam int ROM_ADDR_WIDTH = 8;

    localparam logic [3:0] OP_HLT = 4'b1111;

    localparam int MAX_STEPS = 64;
    localparam int MAX_OUT   = 16;

    logic clk;
    logic rst;

    logic [DATA_WIDTH-1:0] out_a, out_b, out_c, out_d;

    // ---- expected output sequences (built from the program listings) ----------
    logic [DATA_WIDTH-1:0] exp_a [0:MAX_OUT-1];
    logic [DATA_WIDTH-1:0] exp_b [0:MAX_OUT-1];
    logic [DATA_WIDTH-1:0] exp_c [0:MAX_OUT-1];
    logic [DATA_WIDTH-1:0] exp_d [0:MAX_OUT-1];
    int exp_a_n, exp_b_n, exp_c_n, exp_d_n;

    // ---- observed -------------------------------------------------------------
    logic [DATA_WIDTH-1:0] seen_a [0:MAX_OUT-1];
    logic [DATA_WIDTH-1:0] seen_b [0:MAX_OUT-1];
    logic [DATA_WIDTH-1:0] seen_c [0:MAX_OUT-1];
    logic [DATA_WIDTH-1:0] seen_d [0:MAX_OUT-1];
    int seen_a_n, seen_b_n, seen_c_n, seen_d_n;

    int pass_count = 0;
    int fail_count = 0;
    int step_count = 0;

    // ---------------------------------------------------------------------------
    // DUTs + observation taps
    // ---------------------------------------------------------------------------
    top #(
        .DATA_WIDTH(DATA_WIDTH), .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH), .ROM_INIT_FILE("tb/program_a.hex")
    ) dut_a (.clk(clk), .rst(rst), .out(out_a));

    top #(
        .DATA_WIDTH(DATA_WIDTH), .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH), .ROM_INIT_FILE("tb/program_b.hex")
    ) dut_b (.clk(clk), .rst(rst), .out(out_b));

    top #(
        .DATA_WIDTH(DATA_WIDTH), .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH), .ROM_INIT_FILE("tb/program_c.hex")
    ) dut_c (.clk(clk), .rst(rst), .out(out_c));

    top #(
        .DATA_WIDTH(DATA_WIDTH), .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH), .ROM_INIT_FILE("tb/program_d.hex")
    ) dut_d (.clk(clk), .rst(rst), .out(out_d));

    logic [DATA_WIDTH-1:0] dout_a, dout_b, dout_c, dout_d;
    logic                  dvalid_a, dvalid_b, dvalid_c, dvalid_d;

    tb_tap tap_a (.clk(clk), .rst(rst), .rom_data(dut_a.rom_data),
                  .top_out(out_a), .dout(dout_a), .dout_valid(dvalid_a));
    tb_tap tap_b (.clk(clk), .rst(rst), .rom_data(dut_b.rom_data),
                  .top_out(out_b), .dout(dout_b), .dout_valid(dvalid_b));
    tb_tap tap_c (.clk(clk), .rst(rst), .rom_data(dut_c.rom_data),
                  .top_out(out_c), .dout(dout_c), .dout_valid(dvalid_c));
    tb_tap tap_d (.clk(clk), .rst(rst), .rom_data(dut_d.rom_data),
                  .top_out(out_d), .dout(dout_d), .dout_valid(dvalid_d));

    // ---------------------------------------------------------------------------
    // Clock
    // ---------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------
    task automatic do_reset();
        begin
            rst = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    // Advance one clock. After the rising edge the taps hold the OUT values that
    // retired on that edge.
    task automatic step(input bit [3:0] active);
        begin
            @(posedge clk);
            #1;
            if (active[0] && dvalid_a) begin seen_a[seen_a_n] = dout_a; seen_a_n++; end
            if (active[1] && dvalid_b) begin seen_b[seen_b_n] = dout_b; seen_b_n++; end
            if (active[2] && dvalid_c) begin seen_c[seen_c_n] = dout_c; seen_c_n++; end
            if (active[3] && dvalid_d) begin seen_d[seen_d_n] = dout_d; seen_d_n++; end
            step_count++;
        end
    endtask

    // Run until every DUT sits on HLT, or MAX_STEPS is exceeded.
    task automatic run_all(output bit [3:0] halted);
        bit [3:0] done;
        begin
            done       = 4'b0000;
            halted     = 4'b0000;
            step_count = 0;
            while ((done != 4'b1111) && (step_count < MAX_STEPS)) begin
                if (!done[0] && (dut_a.rom_data[7:4] == OP_HLT)) done[0] = 1'b1;
                if (!done[1] && (dut_b.rom_data[7:4] == OP_HLT)) done[1] = 1'b1;
                if (!done[2] && (dut_c.rom_data[7:4] == OP_HLT)) done[2] = 1'b1;
                if (!done[3] && (dut_d.rom_data[7:4] == OP_HLT)) done[3] = 1'b1;
                if (done == 4'b1111) break;
                step(~done);
            end
            halted = done;
        end
    endtask

    task automatic check(input string name,
                         input logic [31:0] got,
                         input logic [31:0] exp);
        begin
            if (got === exp) begin
                pass_count++;
                $display("  PASS  %-28s got=0x%02h", name, got);
            end else begin
                fail_count++;
                $display("  FAIL  %-28s got=0x%02h  exp=0x%02h", name, got, exp);
            end
        end
    endtask

    task automatic check_hlt(input string name, input bit ok);
        begin
            if (ok) begin
                pass_count++;
                $display("  PASS  %-28s", name);
            end else begin
                fail_count++;
                $display("  FAIL  %-28s did not halt within %0d steps", name, MAX_STEPS);
            end
        end
    endtask

    task automatic dump(input string tag,
                        input logic [DATA_WIDTH-1:0] acc,
                        input logic [DATA_WIDTH-1:0] m0,
                        input logic [DATA_WIDTH-1:0] m1);
        begin
            $display("  [state] %-8s A=0x%02h  M[0]=0x%02h  M[1]=0x%02h", tag, acc, m0, m1);
        end
    endtask

    // Report a captured sequence. Arrays are not passed to tasks, so each
    // program gets its own reporter.
    task automatic report_seq_a();
        begin
            if (seen_a_n != exp_a_n) begin
                fail_count++;
                $display("  FAIL  %-28s got=%0d  exp=%0d", "out_a count", seen_a_n, exp_a_n);
            end else begin
                pass_count++;
                $display("  PASS  %-28s got=%0d", "out_a count", seen_a_n);
            end
            for (int i = 0; i < exp_a_n && i < seen_a_n; i++) begin
                if (seen_a[i] === exp_a[i]) begin
                    pass_count++;
                    $display("  PASS  %-28s got=0x%02h", $sformatf("out_a[%0d]", i), seen_a[i]);
                end else begin
                    fail_count++;
                    $display("  FAIL  %-28s got=0x%02h  exp=0x%02h",
                             $sformatf("out_a[%0d]", i), seen_a[i], exp_a[i]);
                end
            end
        end
    endtask

    task automatic report_seq_b();
        begin
            if (seen_b_n != exp_b_n) begin
                fail_count++;
                $display("  FAIL  %-28s got=%0d  exp=%0d", "out_b count", seen_b_n, exp_b_n);
            end else begin
                pass_count++;
                $display("  PASS  %-28s got=%0d", "out_b count", seen_b_n);
            end
            for (int i = 0; i < exp_b_n && i < seen_b_n; i++) begin
                if (seen_b[i] === exp_b[i]) begin
                    pass_count++;
                    $display("  PASS  %-28s got=0x%02h", $sformatf("out_b[%0d]", i), seen_b[i]);
                end else begin
                    fail_count++;
                    $display("  FAIL  %-28s got=0x%02h  exp=0x%02h",
                             $sformatf("out_b[%0d]", i), seen_b[i], exp_b[i]);
                end
            end
        end
    endtask

    task automatic report_seq_c();
        begin
            if (seen_c_n != exp_c_n) begin
                fail_count++;
                $display("  FAIL  %-28s got=%0d  exp=%0d", "out_c count", seen_c_n, exp_c_n);
            end else begin
                pass_count++;
                $display("  PASS  %-28s got=%0d", "out_c count", seen_c_n);
            end
            for (int i = 0; i < exp_c_n && i < seen_c_n; i++) begin
                if (seen_c[i] === exp_c[i]) begin
                    pass_count++;
                    $display("  PASS  %-28s got=0x%02h", $sformatf("out_c[%0d]", i), seen_c[i]);
                end else begin
                    fail_count++;
                    $display("  FAIL  %-28s got=0x%02h  exp=0x%02h",
                             $sformatf("out_c[%0d]", i), seen_c[i], exp_c[i]);
                end
            end
        end
    endtask

    task automatic report_seq_d();
        begin
            if (seen_d_n != exp_d_n) begin
                fail_count++;
                $display("  FAIL  %-28s got=%0d  exp=%0d", "out_d count", seen_d_n, exp_d_n);
            end else begin
                pass_count++;
                $display("  PASS  %-28s got=%0d", "out_d count", seen_d_n);
            end
            for (int i = 0; i < exp_d_n && i < seen_d_n; i++) begin
                if (seen_d[i] === exp_d[i]) begin
                    pass_count++;
                    $display("  PASS  %-28s got=0x%02h", $sformatf("out_d[%0d]", i), seen_d[i]);
                end else begin
                    fail_count++;
                    $display("  FAIL  %-28s got=0x%02h  exp=0x%02h",
                             $sformatf("out_d[%0d]", i), seen_d[i], exp_d[i]);
                end
            end
        end
    endtask

    // ---------------------------------------------------------------------------
    // Cycle trace of DUT B, enabled with +trace
    // ---------------------------------------------------------------------------
    task automatic trace_dut_b();
        begin
            $display("");
            $display("  [trace] t   PC   instr  addr  mem_rdata  wr   A      M[1]");
            while (dut_b.rom_data[7:4] != OP_HLT) begin
                $display("  [trace] %0d   %0d    0x%02h   0x%0h    0x%02h      %0b   0x%02h  0x%02h",
                         step_count, dut_b.rom_addr, dut_b.rom_data,
                         dut_b.mem_addr, dut_b.mem_rdata, dut_b.mem_wr,
                         dut_b.cpu_inst.A, dut_b.mem_inst.mem[1]);
                @(posedge clk);
                #1;
                step_count++;
            end
            @(posedge clk);
            #1;
        end
    endtask

    // ---------------------------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------------------------
    bit [3:0] halted;

    initial begin
        $dumpfile("build/tb_top.vcd");
        $dumpvars(0, tb_top);

        rst = 1'b1;
        seen_a_n = 0; seen_b_n = 0; seen_c_n = 0; seen_d_n = 0;

        // expected output sequences, from the program listings
        exp_a_n = 1; exp_a[0] = 8'h0F;
        exp_b_n = 1; exp_b[0] = 8'h01;
        exp_c_n = 1; exp_c[0] = 8'h0A;
        exp_d_n = 1; exp_d[0] = 8'h0A;

        $display("");
        $display("==============================================================");
        $display(" 8-bit CPU testbench  -- 4 programs run in parallel");
        $display("==============================================================");

        do_reset();
        if ($test$plusargs("trace")) begin
            trace_dut_b();
            do_reset();
        end
        run_all(halted);

        $display("");
        $display(" halted: A=%0b B=%0b C=%0b D=%0b   steps=%0d",
                 halted[0], halted[1], halted[2], halted[3], step_count);

        // -----------------------------------------------------------------------
        $display("");
        $display("[TEST 1] program_a.hex  EXPECT PASS");
        $display("         LDI 0F, STA 0, LDI 00(gap), LDA 0, OUT, HLT");
        check_hlt("HLT reached", halted[0]);
        check("final A", dut_a.cpu_inst.A,      8'h0F);
        check("M[0]",    dut_a.mem_inst.mem[0], 8'h0F);
        report_seq_a();
        dump("prog A", dut_a.cpu_inst.A, dut_a.mem_inst.mem[0], dut_a.mem_inst.mem[1]);

        // -----------------------------------------------------------------------
        $display("");
        $display("[TEST 2] program_b.hex  EXPECT PASS");
        $display("         ADD M[1] -> 5, SUB M[1] -> 1");
        check_hlt("HLT reached", halted[1]);
        check("final A", dut_b.cpu_inst.A,      8'h01);
        check("M[1]",    dut_b.mem_inst.mem[1], 8'h02);
        report_seq_b();
        dump("prog B", dut_b.cpu_inst.A, dut_b.mem_inst.mem[0], dut_b.mem_inst.mem[1]);

        // -----------------------------------------------------------------------
        $display("");
        $display("[TEST 3] program_c.hex  EXPECT PASS");
        $display("         STA 0, LDI 00(gap), LDA 0, OUT, HLT  -- load path is fine");
        check_hlt("HLT reached", halted[2]);
        check("M[0]", dut_c.mem_inst.mem[0], 8'h0A);
        report_seq_c();
        dump("prog C", dut_c.cpu_inst.A, dut_c.mem_inst.mem[0], dut_c.mem_inst.mem[1]);

        // -----------------------------------------------------------------------
        $display("");
        $display("[TEST 4] program_d.hex  EXPECT PASS");
        $display("         LDI 0A, STA 0, LDA 0 back-to-back (no gap), OUT, HLT");
        check_hlt("HLT reached", halted[3]);
        check("M[0]", dut_d.mem_inst.mem[0], 8'h0A);
        report_seq_d();
        dump("prog D", dut_d.cpu_inst.A, dut_d.mem_inst.mem[0], dut_d.mem_inst.mem[1]);

        // -----------------------------------------------------------------------
        $display("");
        $display("==============================================================");
        $display(" RESULT: %0d passed, %0d failed", pass_count, fail_count);
        $display("--------------------------------------------------------------");
        $display(" TEST 1 (basic ld/st/out)      : %s", (seen_a_n == 1 && seen_a[0] === 8'h0F) ? "PASS" : "FAIL");
        $display(" TEST 2 (ADD / SUB)            : %s", (seen_b_n == 1 && seen_b[0] === 8'h01) ? "PASS" : "FAIL");
        $display(" TEST 3 (load with gap)        : %s", (seen_c_n == 1 && seen_c[0] === 8'h0A) ? "PASS" : "FAIL");
        $display(" TEST 4 (gap-less load)        : %s", (seen_d_n == 1 && seen_d[0] === 8'h0A) ? "PASS" : "FAIL");
        $display("--------------------------------------------------------------");
        $display(" MEM reads combinationally (assign rdata = mem[addr]), so a load");
        $display(" sees the value stored in the same cycle. A registered read here");
        $display(" would make ADD/SUB/LDA consume the previous cycle's data.");
        $display("==============================================================");
        $display("");

        if (fail_count != 0)
            $fatal(1, "testbench finished with %0d failing check(s)", fail_count);

        $finish;
    end

    initial begin
        #200000;
        $display("  [warn] global timeout reached");
        $finish;
    end

endmodule
