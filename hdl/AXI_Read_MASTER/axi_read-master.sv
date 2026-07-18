`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: INPT
// Engineer: YOUSSEF FADEL
// 
// Create Date: 09.07.2026 13:47:00
// Design Name: 
// Module Name: axi_read_master
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

module axi_read_master #(
	parameter ADDR_WIDTH = 32,
	parameter DATA_WIDTH = 32,
	parameter STRB_WIDTH = DATA_WIDTH/8
)(
    input  logic                  clk,
    input  logic                  rst,          

    input  logic                  read_en, 
    output logic                  done,
    output logic                  read_err,         

    input  logic [ADDR_WIDTH-1:0] ADDR,
	input  logic [7:0]            BURST_LEN,
	
	// FIFO interface
    output logic [DATA_WIDTH-1:0] FIFO_WDATA,
    output logic                  FIFO_WR_EN,
    input  logic                  FIFO_FULL,
	
	// AXI READ Address Channel
    output logic [ADDR_WIDTH-1:0] ARADDR,
    output logic [7:0]            ARLEN,
    output logic [2:0]            ARSIZE,
    output logic [1:0]            ARBURST,
    output logic                  ARVALID,
    input  logic                  ARREADY,
	
	//AXI READ DATA Channel
	input  logic [DATA_WIDTH-1:0] RDATA,
    input  logic [1:0]            RRESP,
    input  logic                  RLAST,
    input  logic                  RVALID,
    output logic                  RREADY
);
    
	assign ARLEN   = BURST_LEN - 1;
    assign ARSIZE  = $clog2(STRB_WIDTH);   // 2 for 4B, 3 for 8B
    assign ARBURST = 2'b01;                // INCR burst
	
	typedef enum logic [1:0] {
	    IDLE,   
		READ_0,
		READ_1,
		READ_2
	} STATE_T;
	
	STATE_T STATE;
	logic [7:0] beat_cnt;
	logic       resp_err;
	
	always_ff @(posedge clk or posedge rst) begin
	    if(rst) begin
            STATE      <= IDLE;	
		    ARVALID    <= 1'b0;
		    RREADY 	   <= 1'b0;
            FIFO_WR_EN <= 1'b0;
			FIFO_WDATA <= 0;
			beat_cnt   <= 8'b0;
			done       <= 1'b0;
			read_err   <= 1'b0;
			resp_err   <= 1'b0;
		end
		else begin
		    FIFO_WR_EN <= 1'b0;
			done       <= 1'b0; 
			read_err   <= 1'b0;
		    case(STATE)
			    IDLE: begin
				    ARVALID  <= 1'b0;
					RREADY   <= 1'b0;
					beat_cnt <= 8'b0;
					resp_err <= 1'b0;
					if(read_en) begin
					    STATE <= READ_0;
					end
				end
				
				READ_0: begin
				    ARADDR  <= ADDR;
					ARVALID <= 1'b1;
					STATE   <= READ_1;
				end
				
				READ_1: begin
				    if(ARVALID && ARREADY) begin
					    ARVALID <= 1'b0;
						RREADY  <= !FIFO_FULL;
						STATE   <= READ_2;
					end
				end
				
				READ_2: begin
				    RREADY  <= !FIFO_FULL;
					if(RVALID && RREADY) begin
					    FIFO_WDATA <= RDATA;
						FIFO_WR_EN <= 1'b1;
						beat_cnt   <= beat_cnt + 1;
						
						if(RRESP != 2'b00) begin
						    resp_err <= 1'b1;
						end
						if(RLAST) begin
						    RREADY <= 1'b0;
							done   <= 1'b1;
							read_err <= resp_err || (RRESP != 2'b00); 
							STATE  <= IDLE;
						end
					end
				end
				
				default: STATE <= IDLE;
			endcase
		end
	end
endmodule
					    
