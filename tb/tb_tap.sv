`timescale 1ns / 1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_tap -- testbench-only observation helper (NOT part of the CPU).
//
// `top.out` is combinational: `out = (op == OUT) ? A : 0`. It is awkward to
// observe for two reasons:
//
//   1. it drops back to 0 as soon as the OUT instruction leaves the ROM address
//      bus, so it is only meaningful during the OUT cycle;
//   2. it depends on the accumulator, which the rising edge updates. Sampling
//      `out` at that same edge yields the previous instruction's result.
//
// This tap uses a half-cycle discipline instead of racing the edge:
//
//   rising edge   -- the DUT updates its registers
//   falling edge  -- registers and the combinational `out` have settled, and the
//                    instruction is still on the ROM bus; one settled sample is
//                    taken to the `sig`/`val` stage
//   next falling  -- that sample is presented on dout/dout_valid
//
// dout and dout_valid are registered from a single sample point and presented
// together, so they always agree. The testbench reads them at the falling edge.
//
// It observes; it never drives the CPU.
// -----------------------------------------------------------------------------

module tb_tap #(parameter CAPTURE_DELAY = 2) (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] rom_data,   // word currently addressed by the PC
    input  logic [7:0] top_out,    // the DUT's `out` port
    output logic [7:0] dout,
    output logic       dout_valid
);
    logic [7:0] sig;
    logic       val;

    always @(negedge clk) begin
        if (rst) begin
            sig <= 8'h00;
            val <= 1'b0;
        end else begin
            #CAPTURE_DELAY;
            if (rom_data[7:4] == 4'b1110) begin
                sig <= top_out;      // settled: A has the OUT instruction's result
                val <= 1'b1;
            end else begin
                val <= 1'b0;
            end
        end
    end

    assign dout       = sig;
    assign dout_valid = val;
endmodule
