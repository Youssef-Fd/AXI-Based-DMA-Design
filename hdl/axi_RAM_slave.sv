module axi_slave_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 1024          
)(
    input  logic                      clk,
    input  logic                      rst,

    // AXI Read Address Channel
    input  logic [ADDR_WIDTH-1:0]     ARADDR,
    input  logic [7:0]                ARLEN,
    input  logic [2:0]                ARSIZE,      
    input  logic [1:0]                ARBURST,     
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
    input  logic [2:0]                AWSIZE,      
    input  logic [1:0]                AWBURST,     
    input  logic                      AWVALID,
    output logic                      AWREADY,

    // AXI Write Data Channel
    input  logic [DATA_WIDTH-1:0]     WDATA,
    input  logic [DATA_WIDTH/8-1:0]   WSTRB,   
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,

    // AXI Write Response Channel
    output logic [1:0]                BRESP,
    output logic                      BVALID,
    input  logic                      BREADY
);

    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    
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
                        // Load first beat immediately
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
                
                    // Keep VALID asserted while sending data
                    RVALID <= 1'b1;
                    // Wait until master accepts current beat
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
                    WREADY <= 1'b1;   // always ready to accept data

                    if (WVALID && WREADY) begin
                        // Check address bounds
                        if (((w_addr_base >> 2) + w_cnt) < MEM_DEPTH) begin
                            mem[(w_addr_base >> 2) + w_cnt] <= WDATA;
                            BRESP <= 2'b00;          // OKAY
                        end else begin
                            BRESP <= 2'b10;          // SLVERR
                        end

                        w_cnt <= w_cnt + 1;

                        // If this is the last beat, move to response
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
