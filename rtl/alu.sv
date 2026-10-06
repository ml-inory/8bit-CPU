`default_nettype none

// ISA:
// op   opcode      desc
// 0000  LDA    A = M[addr]
// 0001  ADD    A = A + M[addr]
// 0010  SUB    A = A - M[addr]
// 0011  STA    M[addr] = A
// 0100  LDI    A = addr
// 0101  JMP    PC = addr
// 0110  JC     if (C) PC = addr
// 0111  JZ     if (Z) PC = addr
// 1110  OUT    OUT = A
// 1111  HLT    halt

module ALU #(
    parameter WIDTH = 8
) (
    input  logic             clk,
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [3:0]       op,
    output logic [WIDTH-1:0] result,
    output reg               zero,
    output reg               carry_out,
    output logic             wr
);
    logic [WIDTH:0] sum;   // one bit wider, so the carry out is visible

    assign sum = {1'b0, a} + {1'b0, b};

    always_comb begin
        case (op)
            4'b0000: result = b;               // LDA
            4'b0001: result = a + b;           // ADD
            4'b0010: result = a - b;           // SUB
            4'b0011: result = a;               // STA
            4'b0100: result = b;               // LDI
            4'b0101: result = b;               // JMP
            4'b0110: result = b;               // JC
            4'b0111: result = b;               // JZ
            4'b1110: result = a;               // OUT
            4'b1111: result = {WIDTH{1'b0}};   // HLT
            default: result = {WIDTH{1'b0}};   // Default case
        endcase

        wr = (op == 4'b0000) || (op == 4'b0001) || (op == 4'b0010) || (op == 4'b0100); // Write enable for some operation
    end

    always_ff @(posedge clk) begin
        if (op == 4'b0001 || op == 4'b0010) begin
            zero <= (result == {WIDTH{1'b0}});
            // ADD: carry out of the adder.
            // SUB: borrow, i.e. a < b.
            // The carry must come from the widened sum: `result < a` misses the
            // case where the sum wraps all the way round, e.g. 0x80 + 0x80.
            carry_out <= (op == 4'b0001) ? sum[WIDTH] : (op == 4'b0010) ? (a < b) : 1'b0;
        end else begin
            zero <= 1'b0;
            carry_out <= 1'b0;
        end
    end
endmodule