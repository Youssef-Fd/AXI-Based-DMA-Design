`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: INPT
// Engineer: Youssef FADEL
// 
// Create Date: 15.07.2026 21:18:18
// Design Name: 
// Module Name: DMA_Engine
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

`timescale 1ns/1ps

module dma_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = 16
)(
    input logic clk,
    input logic rst,

    //-------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------
    input  logic                  start,
    input  logic [ADDR_WIDTH-1:0] src_addr,
    input  logic [ADDR_WIDTH-1:0] dst_addr,
    input  logic [31:0]           transfer_length,
    input  logic [7:0]            burst_len,

    output logic                  busy,
    output logic                  done,
    output logic                  error,

    //-------------------------------------------------------
    // AXI READ BUS
    //-------------------------------------------------------

    output logic [ADDR_WIDTH-1:0] ARADDR,
    output logic [7:0]            ARLEN,
    output logic [2:0]            ARSIZE,
    output logic [1:0]            ARBURST,
    output logic                  ARVALID,
    input  logic                  ARREADY,

    input  logic [DATA_WIDTH-1:0] RDATA,
    input  logic [1:0]            RRESP,
    input  logic                  RLAST,
    input  logic                  RVALID,
    output logic                  RREADY,

    //-------------------------------------------------------
    // AXI WRITE BUS
    //-------------------------------------------------------

    output logic [ADDR_WIDTH-1:0] AWADDR,
    output logic [7:0]            AWLEN,
    output logic [2:0]            AWSIZE,
    output logic [1:0]            AWBURST,
    output logic                  AWVALID,
    input  logic                  AWREADY,

    output logic [DATA_WIDTH-1:0] WDATA,
    output logic [DATA_WIDTH/8-1:0] WSTRB,
    output logic                  WLAST,
    output logic                  WVALID,
    input  logic                  WREADY,

    input  logic [1:0]            BRESP,
    input  logic                  BVALID,
    output logic                  BREADY
);

////////////////////////////////////////////////////////////
// Controller <-> Masters
////////////////////////////////////////////////////////////

logic read_start;
logic write_start;

logic read_done;
logic write_done;
logic read_error;
logic write_error;

logic [ADDR_WIDTH-1:0] read_addr;
logic [ADDR_WIDTH-1:0] write_addr;

logic [7:0] read_burst_len;
logic [7:0] write_burst_len;

////////////////////////////////////////////////////////////
// FIFO Signals
////////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] fifo_wdata;
logic [DATA_WIDTH-1:0] fifo_rdata;

logic fifo_wr_en;
logic fifo_rd_en;

logic fifo_full;
logic fifo_empty;

////////////////////////////////////////////////////////////
// DMA Controller
////////////////////////////////////////////////////////////

dma_controller controller(

    .clk(clk),
    .rst(rst),

    .start(start),

    .src_addr(src_addr),
    .dst_addr(dst_addr),

    .transfer_length(transfer_length),
    .burst_len(burst_len),

    .busy(busy),
    .done(done),
    .error(error),

    .write_start(write_start),
    .write_addr(write_addr),
    .write_burst_len(write_burst_len),
    .write_done(write_done),
    .write_error(write_error),

    .read_start(read_start),
    .read_addr(read_addr),
    .read_burst_len(read_burst_len),
    .read_done(read_done),
    .read_error(read_error)
);

////////////////////////////////////////////////////////////
// FIFO
////////////////////////////////////////////////////////////

fifo #(
    .WIDTH(DATA_WIDTH),
    .DEPTH(FIFO_DEPTH)
)
fifo_inst(

    .clk(clk),
    .rst(rst),

    .wdata(fifo_wdata),
    .wr_en(fifo_wr_en),
    .full_o(fifo_full),

    .rdata(fifo_rdata),
    .rd_en(fifo_rd_en),
    .empty_o(fifo_empty)
);

////////////////////////////////////////////////////////////
// AXI READ MASTER
////////////////////////////////////////////////////////////

axi_read_master read_master(

    .clk(clk),
    .rst(rst),

    .read_en(read_start),
    .done(read_done),
    .read_err(read_error),

    .ADDR(read_addr),
    .BURST_LEN(read_burst_len),

    .FIFO_WDATA(fifo_wdata),
    .FIFO_WR_EN(fifo_wr_en),
    .FIFO_FULL(fifo_full),

    .ARADDR(ARADDR),
    .ARLEN(ARLEN),
    .ARSIZE(ARSIZE),
    .ARBURST(ARBURST),
    .ARVALID(ARVALID),
    .ARREADY(ARREADY),

    .RDATA(RDATA),
    .RRESP(RRESP),
    .RLAST(RLAST),
    .RVALID(RVALID),
    .RREADY(RREADY)
);

////////////////////////////////////////////////////////////
// AXI WRITE MASTER
////////////////////////////////////////////////////////////

axi_write_master write_master(

    .clk(clk),
    .rst(rst),

    .write_en(write_start),
    .done(write_done),
    .write_err(write_error),

    .ADDR(write_addr),
    .BURST_LEN(write_burst_len),

    .FIFO_RDATA(fifo_rdata),
    .FIFO_EMPTY(fifo_empty),
    .FIFO_RD_EN(fifo_rd_en),

    .AWADDR(AWADDR),
    .AWLEN(AWLEN),
    .AWSIZE(AWSIZE),
    .AWBURST(AWBURST),
    .AWVALID(AWVALID),
    .AWREADY(AWREADY),

    .WDATA(WDATA),
    .WSTRB(WSTRB),
    .WLAST(WLAST),
    .WVALID(WVALID),
    .WREADY(WREADY),

    .BRESP(BRESP),
    .BVALID(BVALID),
    .BREADY(BREADY)
);

endmodule
