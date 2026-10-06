`default_nettype none

module top #(
    parameter DATA_WIDTH = 8,
    parameter MEM_ADDR_WIDTH = 4,
    parameter ROM_ADDR_WIDTH = 8,
    parameter ROM_INIT_FILE = "rom.hex"
) (
    input  logic clk,
    input  logic rst,
    output logic [DATA_WIDTH-1:0] out,
    output logic instr_valid
);
    logic [ROM_ADDR_WIDTH-1:0] rom_addr;
    logic [MEM_ADDR_WIDTH-1:0] mem_addr;
    logic mem_wr;
    logic [DATA_WIDTH-1:0] mem_wdata;
    logic [DATA_WIDTH-1:0] rom_data;
    logic [DATA_WIDTH-1:0] mem_rdata;

    CPU #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH)
    ) cpu_inst (
        .clk(clk),
        .rst(rst),
        .rom_data(rom_data),
        .mem_rdata(mem_rdata),
        .rom_addr(rom_addr),
        .mem_addr(mem_addr),
        .mem_wr(mem_wr),
        .mem_wdata(mem_wdata),
        .out(out),
        .instr_valid(instr_valid)
    );

    ROM #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ROM_ADDR_WIDTH),
        .INIT_FILE(ROM_INIT_FILE)
    ) rom_inst (
        .addr(rom_addr),
        .rdata(rom_data)
    );

    MEM #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(MEM_ADDR_WIDTH)
    ) mem_inst (
        .clk(clk),
        .rst(rst),
        .wr(mem_wr),
        .addr(mem_addr),
        .wdata(mem_wdata),
        .rdata(mem_rdata)
    );
endmodule