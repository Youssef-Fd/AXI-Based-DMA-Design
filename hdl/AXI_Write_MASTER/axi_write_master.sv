`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: INPT
// Engineer: YOUSSEF FADEL
// 
// Create Date: 09.07.2026 13:47:00
// Design Name: 
// Module Name: axi_write_master
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

module axi_write_master #(
	parameter ADDR_WIDTH = 32,
	parameter DATA_WIDTH = 32,
	parameter STRB_WIDTH = DATA_WIDTH/8
)(
    input  logic                  clk,
    input  logic                  rst,          

    input  logic                  write_en, 
    output logic                  done,  
    output logic                  write_err,       

    input  logic [ADDR_WIDTH-1:0] ADDR,  
	input  logic [7:0]            BURST_LEN,

    // FIFO interface
    input  logic [DATA_WIDTH-1:0] FIFO_RDATA,
    input  logic                  FIFO_EMPTY,
    output logic                  FIFO_RD_EN,

    // AXI Write Address Channel
    output logic [ADDR_WIDTH-1:0] AWADDR,
    output logic [7:0]            AWLEN,
    output logic [2:0]            AWSIZE,
    output logic [1:0]            AWBURST,
    output logic                  AWVALID,
    input  logic                  AWREADY,

    // AXI Write Data Channel
    output logic [DATA_WIDTH-1:0] WDATA,
    output logic [STRB_WIDTH-1:0] WSTRB,
    output logic                  WLAST,
    output logic                  WVALID,
    input  logic                  WREADY,

    // AXI Write Response Channel
    input  logic [1:0]            BRESP,
    input  logic                  BVALID,
    output logic                  BREADY
);

    // --------------------------------------------
    // AXI fixed values
    // --------------------------------------------
    assign AWLEN   = BURST_LEN - 1;
    assign AWSIZE  = $clog2(STRB_WIDTH);   // 2 for 4B, 3 for 8B
    assign AWBURST = 2'b01;                // INCR burst
    assign WSTRB   = {STRB_WIDTH{1'b1}};

   
    typedef enum logic [2:0] {
        IDLE_0,
        IDLE_1,
        WRITE_0,
        WRITE_1,
        WRITE_2,
        BRESP_0
    } state_t;

    state_t STATE;
    logic [7:0] beat_cnt;          // counts beats sent

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            STATE      <= IDLE_0;
            AWVALID    <= 1'b0;
            WVALID     <= 1'b0;
            WLAST      <= 1'b0;
            BREADY     <= 1'b0;
            beat_cnt   <= 8'b0;
            FIFO_RD_EN <= 1'b0;
            done       <= 1'b0;
            write_err  <= 1'b0;
        end
		
		else begin
            FIFO_RD_EN <= 1'b0;
            done       <= 1'b0;
            write_err  <= 1'b0;

            case (STATE)
                IDLE_0: begin
                    BREADY <= 1'b0;
                    if (write_en) begin
                        STATE <= IDLE_1;   // one-cycle delay to clear old status
                    end
                end

                IDLE_1: begin
                    // Prepare for write transaction
                    BREADY <= 1'b0;
                    beat_cnt <= 8'b0;
                    if (write_en) begin
                        AWADDR  <= ADDR;
                        AWVALID <= 1'b1;
                        STATE   <= WRITE_0;
                    end
                end

                WRITE_0: begin
                    // Wait for address handshake
                    if (AWREADY) begin
                        AWVALID <= 1'b0;
                        // Prepare first data beat
                        if (!FIFO_EMPTY) begin
                            WDATA  <= FIFO_RDATA;
							FIFO_RD_EN <= 1'b1;
                            WVALID <= 1'b1;
							beat_cnt <= beat_cnt + 1;
                            STATE <= WRITE_1;
                        end 
						/*else begin
                            STATE <= WRITE_0;
                        end */
                    end
                end

                WRITE_1: begin
                    // Wait for data handshake
                    if (WREADY) begin
                        WVALID <= 1'b0;
                        FIFO_RD_EN <= 1'b0;   
                        if (beat_cnt == BURST_LEN) begin
                            WLAST <= 1'b0;
                            STATE <= BRESP_0;
                        end else begin
							STATE <= WRITE_2;
                        end
                    end
                end

                WRITE_2: begin
                    // Load next data word
                    WDATA  <= FIFO_RDATA;
					WVALID <= 1'b1;
					
					FIFO_RD_EN <= 1'b1;
                    if (beat_cnt == BURST_LEN - 1) begin
					    //FIFO_RD_EN <= 1'b0;
                        WLAST      <= 1'b1;
                    end 
                    else begin
					    //FIFO_RD_EN <= 1'b1;
                        WLAST <= 1'b0;
                    end
				    beat_cnt <= beat_cnt + 1;
					STATE <= WRITE_1;
                end

                BRESP_0: begin
                    // Wait for write response
                    if (BVALID) begin
                        BREADY    <= 1'b1;
                        done      <= 1'b1;
                        write_err <= (BRESP != 2'b00);
                        STATE     <= IDLE_0;
                    end
                end

                default: STATE <= IDLE_0;
            endcase
        end
    end

endmodule