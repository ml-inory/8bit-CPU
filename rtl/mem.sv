`default_nettype none

module MEM #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             wr,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic [DATA_WIDTH-1:0] rdata
);
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    integer i;

    always_ff @(posedge clk) begin
        if (rst) begin
            rdata <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end
        else if (wr)
            mem[addr] <= wdata;
        else
            rdata <= mem[addr];
    end
endmodule