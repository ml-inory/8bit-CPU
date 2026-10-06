`default_nettype none

// -----------------------------------------------------------------------------
// tb_tap -- testbench-only observation helper (NOT part of the CPU).
//
// `top.out` is combinational: it presents A while op == OUT and 0 otherwise.
// A testbench that reads it after the clock edge misses the value, because by
// then the PC has advanced and the OUT instruction has left the ROM address
// bus.
//
// This tap latches the real `top.out` pin on the rising edge of the cycle in
// which the OUT instruction is present in the ROM, and raises `dout_valid` for
// one cycle. It observes; it never drives the CPU.
// -----------------------------------------------------------------------------

module tb_tap (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] rom_data,   // word currently addressed by the PC
    input  logic [7:0] top_out,    // the DUT's `out` port
    output logic [7:0] dout,
    output logic       dout_valid
);
    logic [7:0] dout_q;
    logic       valid_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            dout_q  <= 8'h00;
            valid_q <= 1'b0;
        end else begin
            valid_q <= (rom_data[7:4] == 4'b1110);
            if (rom_data[7:4] == 4'b1110)
                dout_q <= top_out;
        end
    end

    assign dout       = dout_q;
    assign dout_valid = valid_q;
endmodule
