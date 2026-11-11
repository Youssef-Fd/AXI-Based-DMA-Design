`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: INPT
// Engineer: Youssef FADEL
// 
// Create Date: 15.07.2026 21:18:18
// Design Name: 
// Module Name: axi_ram_slave
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

module axi_slave_memory #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter MEM_DEPTH    = 1024,        // number of 32-bit words
    parameter INIT_ENABLE  = 0,           // 1 = preload mem[] at power-up
    parameter [DATA_WIDTH-1:0] INIT_BASE = 0  // mem[i] = INIT_BASE + i, if enabled
)(
    input  logic                      clk,
    input  logic                      rst,

    // AXI Read Address Channel
    input  logic [ADDR_WIDTH-1:0]     ARADDR,
    input  logic [7:0]                ARLEN,
    input  logic [2:0]                ARSIZE,      // ignored - only 32-bit accesses
    input  logic [1:0]                ARBURST,     // ignored - only INCR
    input  logic                      ARVALID,
    output logic                      ARREADY,

    // AXI Read Data Channel
    output logic [DATA_WIDTH-1:0]     RDATA,
    output logic [1:0]                RRESP,
    output logic                      RLAST,
    output logic                      RVALID,
    input  logic                      RREADY,

    // AXI Write Address Channel
    input  logic [ADDR_WIDTH-1:0]     AWADDR,
    input  logic [7:0]                AWLEN,
    input  logic [2:0]                AWSIZE,      // ignored - only 32-bit accesses
    input  logic [1:0]                AWBURST,     // ignored - only INCR
    input  logic                      AWVALID,
    output logic                      AWREADY,

    // AXI Write Data Channel
    input  logic [DATA_WIDTH-1:0]     WDATA,
    input  logic [DATA_WIDTH/8-1:0]   WSTRB,    // ignored - full-word writes only
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,

    // AXI Write Response Channel
    output logic [1:0]                BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,

    // -----------------------------------------------------------
    // Plain synchronous debug read port. NOT part of AXI -- exists
    // so a top-level module (e.g. driving a 7-segment display) can
    // observe memory contents using a normal port connection,
    // instead of a cross-module hierarchical reference (which
    // older Quartus versions like 13.0 cannot resolve during
    // synthesis, even though it's legal, simulator-only-safe
    // Verilog). Defaults to address 0 if left unconnected.
    // -----------------------------------------------------------
    input  logic [ADDR_WIDTH-1:0]     DBG_ADDR,
    output logic [DATA_WIDTH-1:0]     DBG_DATA
);

    // --------------------------------------------------------------
    // Memory array with initialisation (for simulation)
    // --------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // --------------------------------------------------------------
    // Optional self-contained power-up preload. This initial block
    // only ever references `mem`, a signal declared in THIS module
    // -- no cross-hierarchy reference involved, so it synthesizes
    // fine (Quartus includes it as the RAM's initial contents in
    // the programming file). Disabled by default (INIT_ENABLE=0),
    // so existing testbenches that preload via other means are
    // unaffected.
    // --------------------------------------------------------------
    integer init_i;
    initial begin
        if (INIT_ENABLE) begin
            for (init_i = 0; init_i < MEM_DEPTH; init_i = init_i + 1)
                mem[init_i] = INIT_BASE + init_i[DATA_WIDTH-1:0];
        end
    end

    // --------------------------------------------------------------
    // Debug read port: plain combinational read, bounds-clamped.
    // --------------------------------------------------------------
    assign DBG_DATA = ((DBG_ADDR >> 2) < MEM_DEPTH) ? mem[DBG_ADDR >> 2] : '0;

    // --------------------------------------------------------------
    // Read FSM - RLAST is driven before the handshake, and RVALID
    // stays high until the next cycle.
    // --------------------------------------------------------------
    localparam R_IDLE = 2'd0, R_SEND = 2'd1;

    logic [1:0] r_state;
    logic [7:0] r_cnt;
    logic [ADDR_WIDTH-1:0] r_addr_base;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_state     <= R_IDLE;
            ARREADY     <= 1'b0;
            RVALID      <= 1'b0;
            RDATA       <= 0;
            RRESP       <= 2'b00;
            RLAST       <= 1'b0;
            r_cnt       <= 0;
            r_addr_base <= 0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    ARREADY <= 1'b1;
                    RVALID  <= 1'b0;
                    RLAST   <= 1'b0;
                    RRESP   <= 2'b00;
                    if (ARVALID && ARREADY) begin
                        ARREADY     <= 1'b0;
                        r_addr_base <= ARADDR;
                        r_cnt       <= 0;
                        r_state     <= R_SEND;
                        if ((ARADDR >> 2) < MEM_DEPTH) begin
                            RDATA <= mem[ARADDR >> 2];
                            RRESP <= 2'b00;
                        end
                        else begin
                            RDATA <= '0;
                            RRESP <= 2'b10;
                        end
                        RLAST  <= (ARLEN == 0);
                        RVALID <= 1'b1;
                    end
                end

                R_SEND: begin
                    RVALID <= 1'b1;
                    if (RREADY) begin
                        if (r_cnt == ARLEN) begin
                            RVALID  <= 1'b0;
                            RLAST   <= 1'b0;
                            ARREADY <= 1'b1;
                            r_state <= R_IDLE;
                        end
                        else begin
                            r_cnt <= r_cnt + 1;
                            if (((r_addr_base >> 2) + r_cnt + 1) < MEM_DEPTH) begin
                                RDATA <= mem[(r_addr_base >> 2) + r_cnt + 1];
                                RRESP <= 2'b00;
                            end
                            else begin
                                RDATA <= '0;
                                RRESP <= 2'b10;
                            end
                            RLAST <= ((r_cnt + 1) == ARLEN);
                        end
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

    // --------------------------------------------------------------
    // Write FSM
    // --------------------------------------------------------------
    localparam W_IDLE = 2'd0, W_DATA = 2'd1, W_RESP = 2'd2;

    logic [1:0] w_state;
    logic [7:0] w_cnt;
    logic [ADDR_WIDTH-1:0] w_addr_base;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            w_state      <= W_IDLE;
            AWREADY      <= 1'b0;
            WREADY       <= 1'b0;
            BVALID       <= 1'b0;
            BRESP        <= 2'b00;
            w_cnt        <= 0;
            w_addr_base  <= 0;

        end else begin
            case (w_state)
                W_IDLE: begin
                    AWREADY <= 1'b1;
                    WREADY  <= 1'b0;
                    BVALID  <= 1'b0;
                    BRESP   <= 2'b00;
                    if (AWVALID && AWREADY) begin
                        AWREADY     <= 1'b0;
                        w_addr_base <= AWADDR;
                        w_cnt       <= 0;
                        WREADY      <= 1'b1;
                        w_state     <= W_DATA;
                    end
                end

                W_DATA: begin
                    WREADY <= 1'b1;

                    if (WVALID && WREADY) begin
                        if (((w_addr_base >> 2) + w_cnt) < MEM_DEPTH) begin
                            mem[(w_addr_base >> 2) + w_cnt] <= WDATA;
                            BRESP <= 2'b00;
                        end else begin
                            BRESP <= 2'b10;
                        end

                        w_cnt <= w_cnt + 1;

                        if (WLAST) begin
                            WREADY  <= 1'b0;
                            w_state <= W_RESP;
                        end
                    end
                end

                W_RESP: begin
                    BVALID <= 1'b1;
                    if (BVALID && BREADY) begin
                        BVALID <= 1'b0;
                        w_state <= W_IDLE;
                    end
                end

                default: w_state <= W_IDLE;
            endcase
        end
    end
    

endmodule
