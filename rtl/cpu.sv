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

module CPU #(
    parameter DATA_WIDTH = 8,
    parameter MEM_ADDR_WIDTH = 4,
    parameter ROM_ADDR_WIDTH = 8
) (
    input  logic clk,
    input  logic rst,
    input  logic [DATA_WIDTH-1:0] rom_data,
    input  logic [DATA_WIDTH-1:0] mem_rdata,
    output logic [ROM_ADDR_WIDTH-1:0] rom_addr,
    output logic [MEM_ADDR_WIDTH-1:0] mem_addr,
    output logic mem_wr,
    output logic [DATA_WIDTH-1:0] mem_wdata,
    output logic [DATA_WIDTH-1:0] out
);
    reg [DATA_WIDTH-1:0] A; // Accumulator
    logic [DATA_WIDTH-1:0] B; // Temporary register for ALU operations
    reg [ROM_ADDR_WIDTH-1:0] PC; // Program Counter

    logic [ROM_ADDR_WIDTH/2-1:0] op;
    logic [ROM_ADDR_WIDTH/2-1:0] addr;

    logic [DATA_WIDTH-1:0] alu_result;
    logic alu_zero;
    logic alu_carry_out;
    logic alu_wr;

    logic pc_load;

    assign op = rom_data[ROM_ADDR_WIDTH-1:ROM_ADDR_WIDTH/2];
    assign addr = rom_data[ROM_ADDR_WIDTH/2-1:0];
    assign rom_addr = PC;
    assign mem_addr = addr;
    assign mem_wdata = alu_result;
    assign mem_wr = (op == 4'b0011);
    assign out = (op == 4'b1110) ? A : {DATA_WIDTH{1'b0}};
    assign pc_load = (op == 4'b0101) || (op == 4'b0110 && alu_carry_out) || (op == 4'b0111 && alu_zero);
    assign B = (op == 4'b0000 || op == 4'b0001 || op == 4'b0010) ? mem_rdata : addr;

    ALU #(
        .WIDTH(DATA_WIDTH)
    ) alu_inst (
        .clk(clk),
        .a(A),
        .b(B),
        .op(op),
        .result(alu_result),
        .zero(alu_zero),
        .carry_out(alu_carry_out),
        .wr(alu_wr)
    );

    PC #(
        .WIDTH(ROM_ADDR_WIDTH)
    ) pc_inst (
        .clk(clk),
        .rst(rst),
        .load(pc_load),
        .data_in(addr),
        .pc_out(PC)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            A <= {DATA_WIDTH{1'b0}};
        end else begin
            if (alu_wr) begin
                A <= alu_result;
            end
        end
    end

endmodule