`default_nettype none

module PC #(
    parameter WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             load,
    input  logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] pc_out
);

    always_ff @(posedge clk) begin
        if (rst)
            pc_out <= {WIDTH{1'b0}};
        else if (load)
            pc_out <= data_in;
        else
            pc_out <= pc_out + 1;
    end
endmodule