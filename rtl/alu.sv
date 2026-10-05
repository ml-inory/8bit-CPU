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

module alu #(
    parameter WIDTH = 8
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [3:0]       op,
    output logic [WIDTH-1:0] result,
    output logic             zero,
    output logic             carry_out
);

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
            4'b1111: result = {WIDTH{1'b0}};  // HLT
            default: result = {WIDTH{1'b0}};   // Default case
        endcase

        zero = (result == {WIDTH{1'b0}});
        carry_out = (op == 4'b0001) ? (result < a) : (op == 4'b0010) ? (a < b) : 1'b0;
    end
endmodule