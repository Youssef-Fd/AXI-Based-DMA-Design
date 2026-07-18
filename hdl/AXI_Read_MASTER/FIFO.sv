`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: INPT
// Engineer: Youssef FADEL
// 
// Create Date: 11.07.2026 12:56:15
// Design Name: 
// Module Name: FIFO
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
)(
    input  logic             clk,
    input  logic             rst,

    //-------------------------
    // Write Interface
    //-------------------------
    input  logic [WIDTH-1:0] wdata,
    input  logic             wr_en,
    output logic             full_o,

    //-------------------------
    // Read Interface
    //-------------------------
    output logic [WIDTH-1:0] rdata,
    input  logic             rd_en,
    output logic             empty_o
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    logic [ADDR_WIDTH-1:0] wptr;
    logic [ADDR_WIDTH-1:0] rptr;
    logic [ADDR_WIDTH:0]   count;

    assign empty_o = (count == 0);
    assign full_o  = (count == DEPTH);

    assign rdata = mem[rptr];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wptr  <= 0;
            rptr  <= 0;
            count <= 0;
        end else begin
            case ({wr_en && !full_o, rd_en && !empty_o})

                //--------------------------------------------------
                // Write only
                //--------------------------------------------------
                2'b10: begin
                    mem[wptr] <= wdata;
                    wptr  <= (wptr == DEPTH-1) ? '0 : wptr + 1'b1;
                    count <= count + 1'b1;
                end

                //--------------------------------------------------
                // Read only
                //--------------------------------------------------
                2'b01: begin
                    rptr  <= (rptr == DEPTH-1) ? '0 : rptr + 1'b1;
                    count <= count - 1'b1;
                end

                //--------------------------------------------------
                // Simultaneous read and write: one in, one out,
                // count stays the same.
                //--------------------------------------------------
                2'b11: begin
                    mem[wptr] <= wdata;
                    wptr <= (wptr == DEPTH-1) ? '0 : wptr + 1'b1;
                    rptr <= (rptr == DEPTH-1) ? '0 : rptr + 1'b1;
                end

                default: ;

            endcase
        end
    end

endmodule