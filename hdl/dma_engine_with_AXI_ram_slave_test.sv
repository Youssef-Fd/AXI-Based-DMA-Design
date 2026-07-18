`timescale 1ns/1ps

module tb_dma_top;

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter FIFO_DEPTH = 16;
    parameter MEM_DEPTH  = 1024;      // words, per memory
    parameter CLK_PERIOD = 10;

    logic clk;
    logic rst;

    always #(CLK_PERIOD/2) clk = ~clk;

    //---------------------------------------------------------
    // DMA control interface
    //---------------------------------------------------------
    logic                  start;
    logic [ADDR_WIDTH-1:0] src_addr;
    logic [ADDR_WIDTH-1:0] dst_addr;
    logic [31:0]           transfer_length;
    logic [7:0]             burst_len;
    logic                   busy;
    logic                   done;
    logic                   error;

    //---------------------------------------------------------
    // Read bus: dma_engine -> source memory
    //---------------------------------------------------------
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [7:0]              ARLEN;
    logic [2:0]               ARSIZE;
    logic [1:0]               ARBURST;
    logic                     ARVALID;
    logic                     ARREADY;
    logic [DATA_WIDTH-1:0]   RDATA;
    logic [1:0]               RRESP;
    logic                     RLAST;
    logic                     RVALID;
    logic                     RREADY;

    //---------------------------------------------------------
    // Write bus: dma_engine -> destination memory
    //---------------------------------------------------------
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [7:0]               AWLEN;
    logic [2:0]               AWSIZE;
    logic [1:0]               AWBURST;
    logic                     AWVALID;
    logic                     AWREADY;
    logic [DATA_WIDTH-1:0]   WDATA;
    logic [DATA_WIDTH/8-1:0] WSTRB;
    logic                     WLAST;
    logic                     WVALID;
    logic                     WREADY;
    logic [1:0]               BRESP;
    logic                     BVALID;
    logic                     BREADY;

    //---------------------------------------------------------
    // DUT: the full DMA engine
    //---------------------------------------------------------
    dma_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk), .rst(rst),

        .start(start),
        .src_addr(src_addr),
        .dst_addr(dst_addr),
        .transfer_length(transfer_length),
        .burst_len(burst_len),
        .busy(busy),
        .done(done),
        .error(error),

        .ARADDR(ARADDR), .ARLEN(ARLEN), .ARSIZE(ARSIZE), .ARBURST(ARBURST),
        .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST), .RVALID(RVALID), .RREADY(RREADY),

        .AWADDR(AWADDR), .AWLEN(AWLEN), .AWSIZE(AWSIZE), .AWBURST(AWBURST),
        .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY)
    );

    //---------------------------------------------------------
    // Source memory: dma_engine reads FROM here
    //---------------------------------------------------------
    axi_slave_memory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(MEM_DEPTH)
    ) u_src_mem (
        .clk(clk), .rst(rst),

        .ARADDR(ARADDR), .ARLEN(ARLEN), .ARSIZE(ARSIZE), .ARBURST(ARBURST),
        .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST), .RVALID(RVALID), .RREADY(RREADY),

        // This memory is never written by this testbench over AXI --
        // it's preloaded directly (hierarchical access) below. Tie the
        // unused write channel off so it can't interfere.
        .AWADDR('0), .AWLEN('0), .AWSIZE('0), .AWBURST('0),
        .AWVALID(1'b0), .AWREADY(),
        .WDATA('0), .WSTRB('0), .WLAST(1'b0), .WVALID(1'b0), .WREADY(),
        .BRESP(), .BVALID(), .BREADY(1'b0)
    );

    //---------------------------------------------------------
    // Destination memory: dma_engine writes TO here
    //---------------------------------------------------------
    axi_slave_memory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(MEM_DEPTH)
    ) u_dst_mem (
        .clk(clk), .rst(rst),

        // This memory is never read by this testbench over AXI -- it's
        // checked directly (hierarchical access) below. Tie the unused
        // read channel off.
        .ARADDR('0), .ARLEN('0), .ARSIZE('0), .ARBURST('0),
        .ARVALID(1'b0), .ARREADY(),
        .RDATA(), .RRESP(), .RLAST(), .RVALID(), .RREADY(1'b0),

        .AWADDR(AWADDR), .AWLEN(AWLEN), .AWSIZE(AWSIZE), .AWBURST(AWBURST),
        .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY)
    );

    int errors;

    //---------------------------------------------------------
    // Read-beat scoreboard for Test 3: while armed, checks each
    // accepted read beat against an expected (data, resp) pair.
    // Disarmed for tests 1/2, which check final memory contents
    // instead.
    //---------------------------------------------------------
    logic                   t3_check_armed;
    int                     t3_beat_idx;
    logic [DATA_WIDTH-1:0]  t3_expected_data [0:7];   // only beats 0-7 have known data

    always @(posedge clk) begin
        if (RVALID && RREADY && t3_check_armed) begin
            if (t3_beat_idx < 8) begin
                if (RRESP !== 2'b00) begin
                    $display("[%0t] ERROR: Test 3 beat %0d should be OKAY (in-bounds), got RRESP=%0d",
                              $time, t3_beat_idx, RRESP);
                    errors++;
                end
                if (RDATA !== t3_expected_data[t3_beat_idx]) begin
                    $display("[%0t] MISMATCH: Test 3 beat %0d expected 0x%0h, got 0x%0h",
                              $time, t3_beat_idx, t3_expected_data[t3_beat_idx], RDATA);
                    errors++;
                end
            end else begin
                if (RRESP !== 2'b10) begin
                    $display("[%0t] ERROR: Test 3 beat %0d should be SLVERR (out-of-bounds), got RRESP=%0d",
                              $time, t3_beat_idx, RRESP);
                    errors++;
                end
            end
            t3_beat_idx++;
        end
    end

    //---------------------------------------------------------
    // Helper: run one DMA transfer and wait for it to settle
    // into either done or error. Times out if neither happens.
    //---------------------------------------------------------
    task automatic run_dma(
        input logic [ADDR_WIDTH-1:0] s_addr,
        input logic [ADDR_WIDTH-1:0] d_addr,
        input int                    len,
        input int                    blen
    );
        int timeout;
        begin
            @(negedge clk);
            src_addr        <= s_addr;
            dst_addr        <= d_addr;
            transfer_length <= len;
            burst_len       <= blen;
            start           <= 1'b1;

            @(negedge clk);
            start <= 1'b0;

            timeout = 0;
            while (!done && !error && timeout < 5000) begin
                @(posedge clk);
                timeout++;
            end

            if (timeout >= 5000) begin
                $display("[%0t] ERROR: DMA transfer timed out waiting for done/error", $time);
                errors++;
            end
        end
    endtask

    //---------------------------------------------------------
    // Stimulus
    //---------------------------------------------------------
    integer i;

    initial begin
        clk = 0;
        rst = 1;

        start = 0; src_addr = 0; dst_addr = 0;
        transfer_length = 0; burst_len = 0;

        errors = 0;

        #(5*CLK_PERIOD);
        rst = 0;
        #(2*CLK_PERIOD);

        //=================================================
        // Test 1: clean, single-burst transfer (16 words)
        //=================================================
        $display("--------------------------------------------------");
        $display("Test 1: single-burst transfer, 16 words");
        $display("--------------------------------------------------");

        for (i = 0; i < 16; i = i + 1)
            u_src_mem.mem[i] = 32'hA000_0000 + i;
        for (i = 0; i < 16; i = i + 1)
            u_dst_mem.mem[i] = 32'hDEAD_DEAD;   // poison, so a no-op write is visible

        run_dma(32'h0000_0000, 32'h0000_0000, 16, 16);

        if (error) begin
            $display("[%0t] ERROR: Test 1 unexpectedly reported error", $time);
            errors++;
        end
        for (i = 0; i < 16; i = i + 1) begin
            if (u_dst_mem.mem[i] !== u_src_mem.mem[i]) begin
                $display("[%0t] MISMATCH word %0d: src=0x%0h dst=0x%0h",
                          $time, i, u_src_mem.mem[i], u_dst_mem.mem[i]);
                errors++;
            end
        end
        $display("[%0t] Test 1 done (busy=%0b done=%0b error=%0b)", $time, busy, done, error);

        #(4*CLK_PERIOD);

        //=================================================
        // Test 2: multi-burst transfer, NOT a multiple of
        // burst_len (20 words, burst_len=16 -> 16 + 4)
        //=================================================
        $display("--------------------------------------------------");
        $display("Test 2: multi-burst transfer, 20 words / burst_len=16");
        $display("--------------------------------------------------");

        for (i = 0; i < 20; i = i + 1)
            u_src_mem.mem[100+i] = 32'hB000_0000 + i;
        for (i = 0; i < 20; i = i + 1)
            u_dst_mem.mem[200+i] = 32'hDEAD_DEAD;

        run_dma(100*4, 200*4, 20, 16);

        if (error) begin
            $display("[%0t] ERROR: Test 2 unexpectedly reported error", $time);
            errors++;
        end
        for (i = 0; i < 20; i = i + 1) begin
            if (u_dst_mem.mem[200+i] !== u_src_mem.mem[100+i]) begin
                $display("[%0t] MISMATCH word %0d: src=0x%0h dst=0x%0h",
                          $time, i, u_src_mem.mem[100+i], u_dst_mem.mem[200+i]);
                errors++;
            end
        end
        $display("[%0t] Test 2 done (busy=%0b done=%0b error=%0b)", $time, busy, done, error);

        #(4*CLK_PERIOD);

        //=================================================
        // Test 3: transfer that reads past the end of the
        // source memory -- expect the DMA to report `error`
        // (propagated from axi_read_master's read_error, via
        // dma_controller's read_error input / ERROR_STATE).
        //=================================================
        $display("--------------------------------------------------");
        $display("Test 3: out-of-bounds source read -> expect dma_engine error");
        $display("--------------------------------------------------");

        // Start 8 words before the end of a MEM_DEPTH-word memory,
        // request 16 -- the last 8 words run past MEM_DEPTH.
        // Preload the in-bounds half (MEM_DEPTH-8 .. MEM_DEPTH-1) with
        // known data first, so those 8 beats are genuine, checkable
        // OKAY reads with real data -- only the truly out-of-bounds
        // beats should ever report SLVERR.
        for (i = 0; i < 8; i = i + 1) begin
            u_src_mem.mem[MEM_DEPTH-8+i] = 32'hC0FF_EE00 + i;
            t3_expected_data[i] = 32'hC0FF_EE00 + i;
        end

        t3_beat_idx    = 0;
        t3_check_armed = 1'b1;

        run_dma((MEM_DEPTH-8)*4, 0, 16, 16);

        t3_check_armed = 1'b0;

        if (t3_beat_idx != 16) begin
            $display("[%0t] ERROR: Test 3 only saw %0d read beats, expected 16", $time, t3_beat_idx);
            errors++;
        end

        if (!error) begin
            $display("[%0t] ERROR: expected dma_engine `error` to assert for an out-of-bounds read burst", $time);
            errors++;
        end else begin
            $display("[%0t] Confirmed: dma_engine correctly reported error on out-of-bounds read.", $time);
        end
        $display("[%0t] Test 3 done (busy=%0b done=%0b error=%0b)", $time, busy, done, error);

        //=================================================
        // Summary
        //=================================================
        if (errors == 0)
            $display("TEST PASSED: dma_engine + axi_slave_memory integration checks all passed.");
        else
            $display("TEST FAILED with %0d error(s).", errors);

        #(CLK_PERIOD*5);
        $finish;
    end

    //---------------------------------------------------------
    // Monitor
    //---------------------------------------------------------
    always @(posedge clk) begin
        if (RVALID && RREADY)
            $display("[%0t] READ  beat: RDATA=0x%0h RRESP=%0d RLAST=%0b", $time, RDATA, RRESP, RLAST);
        if (WVALID && WREADY)
            $display("[%0t] WRITE beat: WDATA=0x%0h WLAST=%0b", $time, WDATA, WLAST);
        if (BVALID && BREADY)
            $display("[%0t] BRESP=%0d", $time, BRESP);
    end

endmodule