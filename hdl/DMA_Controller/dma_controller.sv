`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Youssef FADEL
// 
// Create Date: 15.07.2026 19:26:28
// Design Name: 
// Module Name: dma_controller
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


module dma_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic clk,
	input  logic rst,
	
	input  logic start,
	
	input  logic [ADDR_WIDTH-1:0] src_addr,
	input  logic [ADDR_WIDTH-1:0] dst_addr,
	
	input  logic [31:0]           transfer_length,
    input  logic [7:0]            burst_len,
	
	output logic                  busy,
    output logic                  done,
    output logic                  error,
	
    // Write Master Interface
    output logic                  write_start,
    output logic [ADDR_WIDTH-1:0] write_addr,
    output logic [7:0]            write_burst_len,
    input  logic                  write_done,
    input  logic                  write_error,
	
    // Read Master Interface
    output logic                  read_start,
    output logic [ADDR_WIDTH-1:0] read_addr,
    output logic [7:0]            read_burst_len,
    input  logic                  read_done,
    input  logic                  read_error
);
	typedef enum logic [3:0] {
        IDLE,
        START_READ,
        WAIT_READ,
        START_WRITE_0,
        START_WRITE_1,
        WAIT_WRITE,
        FINISHED,
        ERROR_STATE
    } STATE_T;
	
	STATE_T STATE;
	logic [31:0] remaining_words;
	logic [7:0]  burst_size;
    logic        last_burst;
	
	// DMA Controller
	always_ff @(posedge clk or posedge rst) begin
	    if(rst) begin 
            STATE           <= IDLE;
            busy            <= 0;
            done            <= 0;
            error           <= 0;
            read_start      <= 0;
            write_start     <= 0;
            read_burst_len  <= 0;
            write_burst_len <= 0;
            remaining_words <= 0;
            burst_size      <= 0;
            last_burst      <= 0;
		end
		else begin
		    read_start  <= 0;
            write_start <= 0;
            done        <= 0;
			error       <= 0;
			case(STATE) 
		        IDLE: begin
				    busy <= 1'b0;
                    if(start && (transfer_length != 0)) begin
                        busy            <= 1;
                        read_addr       <= src_addr;
                        write_addr      <= dst_addr;
                        remaining_words <= transfer_length;
                        STATE           <= START_READ;
                    end
				end
				
				START_READ: begin 
			        if(remaining_words <= {24'b0, burst_len}) begin
                        burst_size      <= remaining_words[7:0];
                        last_burst      <= 1'b1;
                        read_burst_len  <= remaining_words[7:0];
                        write_burst_len <= remaining_words[7:0];
                    end
                    else begin
                        burst_size      <= burst_len;
                        last_burst      <= 1'b0;
                        read_burst_len  <= burst_len;
                        write_burst_len <= burst_len;
                    end
                    read_start <= 1'b1;
                    STATE      <= WAIT_READ;
				end
				
				WAIT_READ: begin
				    if(read_done) begin
					    if(read_error)
						    STATE <= ERROR_STATE;
						else
						    STATE <= START_WRITE_0;
					end
				end
				
				START_WRITE_0: begin
				    write_start <= 1'b1;
					STATE       <= START_WRITE_1;
				end
				
				START_WRITE_1: begin
				    write_start <= 1'b1;
					STATE       <= WAIT_WRITE;
				end 
				
				WAIT_WRITE: begin
				    if(write_done) begin
					    if(write_error)
						    STATE <= ERROR_STATE;
					    else if(last_burst) begin
						    STATE <= FINISHED;
						end
						else begin 
						    remaining_words <= remaining_words - burst_size;
							/*
							bumps read_addr/write_addr forward by burst_size*(DATA_WIDTH/8) bytes,
							so the next burst continues from where the last one left off,
							not from the start again. 
							*/
							read_addr       <= read_addr  + burst_size*(DATA_WIDTH/8); 
							write_addr      <= write_addr + burst_size*(DATA_WIDTH/8);
							STATE           <= START_READ;
						end
					end
				end
				
				FINISHED: begin
				    busy  <= 1'b0;
					done  <= 1'b1;
					STATE <= IDLE;
				end
				
				ERROR_STATE: begin
				    busy  <= 0;
				    done  <= 0;
					error <= 1;
					STATE <= IDLE;
				end

				default: STATE <= IDLE;
			endcase
		end
	end
endmodule
