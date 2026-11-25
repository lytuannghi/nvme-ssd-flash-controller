// =============================================================================
// File: tb_nvme_ssd_controller.v
// Module: tb_nvme_ssd_controller
// Project: Enterprise NVMe PCIe Gen3 SSD Controller ASIC
// Description: Comprehensive Self-Checking Testbench executing 10 verification
//              test suites through external pins with zero internal pokes.
// =============================================================================

`timescale 1ns / 1ps

module tb_nvme_ssd_controller;

    localparam CHANNELS = 8;

    reg                 clk;
    reg                 rst_n;

    // Host Doorbell Register Interface
    reg                 host_db_wr_en;
    reg  [7:0]          host_db_addr;
    reg  [15:0]         host_db_val;

    // Host Command Ingestion Interface
    reg                 host_cmd_valid;
    reg  [31:0]         host_cmd_dw0;
    reg  [31:0]         host_cmd_dw1;
    reg  [31:0]         host_cmd_dw10;
    reg  [31:0]         host_cmd_dw11;
    reg  [31:0]         host_cmd_dw12;
    wire                host_cmd_ready;

    // Host Completion Queue DMA Interface
    wire                host_cqe_valid;
    wire [127:0]        host_cqe_data;
    wire                host_msix_irq;

    // Physical Toggle DDR NAND Flash Interface (8 Channels, Packed)
    wire [CHANNELS-1:0]   nand_cle;
    wire [CHANNELS-1:0]   nand_ale;
    wire [CHANNELS-1:0]   nand_ce_n;
    wire [CHANNELS-1:0]   nand_we_n;
    wire [CHANNELS-1:0]   nand_re_n;
    wire [CHANNELS-1:0]   nand_dqs;
    wire [CHANNELS*8-1:0] nand_dq_out;
    reg  [CHANNELS*8-1:0] nand_dq_in;

    // Host BCH ECC Direct Interface
    reg                 host_ecc_enc_start;
    reg  [63:0]         host_ecc_enc_data;
    reg                 host_ecc_enc_valid;
    wire                host_ecc_enc_done;
    wire [63:0]         host_ecc_enc_parity;
    reg                 host_ecc_dec_start;
    reg  [63:0]         host_ecc_dec_data;
    reg                 host_ecc_dec_valid;
    reg  [63:0]         host_ecc_dec_parity;
    wire                host_ecc_dec_done;
    wire [63:0]         host_ecc_dec_corrected;
    wire [4:0]          host_ecc_dec_errors;
    wire                host_ecc_dec_uncorr;

    // Host FTL Maintenance Interface
    reg                 host_erase_req;
    reg  [9:0]          host_erase_block_idx;

    // Status Telemetry
    wire                status_cmd_pending;
    wire                status_gc_needed;
    wire [15:0]         status_max_erase_count;

    integer tests_passed = 0;
    integer tests_failed = 0;
    integer c;

    // Sticky event monitors
    reg         saw_host_cqe;
    reg         saw_msix_irq;
    reg         saw_ch5_ce;
    reg         saw_dqs_toggle;
    reg         saw_ecc_enc_done;
    reg [63:0]  latched_enc_parity;
    reg         saw_ecc_dec_done;
    reg [63:0]  latched_dec_corrected;
    reg [4:0]   latched_dec_errors;
    reg         latched_dec_uncorr;
    reg [7:0]   prev_dqs;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_host_cqe          <= 1'b0;
            saw_msix_irq          <= 1'b0;
            saw_ch5_ce            <= 1'b0;
            saw_dqs_toggle        <= 1'b0;
            saw_ecc_enc_done      <= 1'b0;
            latched_enc_parity    <= 64'd0;
            saw_ecc_dec_done      <= 1'b0;
            latched_dec_corrected <= 64'd0;
            latched_dec_errors    <= 5'd0;
            latched_dec_uncorr    <= 1'b0;
            prev_dqs              <= 8'd0;
        end else begin
            if (host_cqe_valid)   saw_host_cqe <= 1'b1;
            if (host_msix_irq)    saw_msix_irq <= 1'b1;
            if (!nand_ce_n[5])    saw_ch5_ce   <= 1'b1;
            if (nand_dqs != prev_dqs) saw_dqs_toggle <= 1'b1;
            prev_dqs <= nand_dqs;

            if (host_ecc_enc_done) begin
                saw_ecc_enc_done   <= 1'b1;
                latched_enc_parity <= host_ecc_enc_parity;
            end
            if (host_ecc_dec_done) begin
                saw_ecc_dec_done      <= 1'b1;
                latched_dec_corrected <= host_ecc_dec_corrected;
                latched_dec_errors    <= host_ecc_dec_errors;
                latched_dec_uncorr    <= host_ecc_dec_uncorr;
            end
        end
    end

    // DUT Instantiation
    nvme_ssd_controller_top #(
        .CHANNELS(CHANNELS)
    ) u_dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .host_db_wr_en         (host_db_wr_en),
        .host_db_addr          (host_db_addr),
        .host_db_val           (host_db_val),
        .host_cmd_valid        (host_cmd_valid),
        .host_cmd_dw0          (host_cmd_dw0),
        .host_cmd_dw1          (host_cmd_dw1),
        .host_cmd_dw10         (host_cmd_dw10),
        .host_cmd_dw11         (host_cmd_dw11),
        .host_cmd_dw12         (host_cmd_dw12),
        .host_cmd_ready        (host_cmd_ready),
        .host_cqe_valid        (host_cqe_valid),
        .host_cqe_data         (host_cqe_data),
        .host_msix_irq         (host_msix_irq),
        .nand_cle              (nand_cle),
        .nand_ale              (nand_ale),
        .nand_ce_n             (nand_ce_n),
        .nand_we_n             (nand_we_n),
        .nand_re_n             (nand_re_n),
        .nand_dqs              (nand_dqs),
        .nand_dq_out           (nand_dq_out),
        .nand_dq_in            (nand_dq_in),
        .host_ecc_enc_start    (host_ecc_enc_start),
        .host_ecc_enc_data     (host_ecc_enc_data),
        .host_ecc_enc_valid    (host_ecc_enc_valid),
        .host_ecc_enc_done     (host_ecc_enc_done),
        .host_ecc_enc_parity   (host_ecc_enc_parity),
        .host_ecc_dec_start    (host_ecc_dec_start),
        .host_ecc_dec_data     (host_ecc_dec_data),
        .host_ecc_dec_valid    (host_ecc_dec_valid),
        .host_ecc_dec_parity   (host_ecc_dec_parity),
        .host_ecc_dec_done     (host_ecc_dec_done),
        .host_ecc_dec_corrected(host_ecc_dec_corrected),
        .host_ecc_dec_errors   (host_ecc_dec_errors),
        .host_ecc_dec_uncorr   (host_ecc_dec_uncorr),
        .host_erase_req        (host_erase_req),
        .host_erase_block_idx  (host_erase_block_idx),
        .status_cmd_pending    (status_cmd_pending),
        .status_gc_needed      (status_gc_needed),
        .status_max_erase_count(status_max_erase_count)
    );

    // 250 MHz System Clock (4.0 ns period)
    always #2.0 clk = ~clk;

    task submit_nvme_cmd;
        input [15:0] cid;
        input [7:0]  opcode;
        input [31:0] nsid;
        input [31:0] dw10;
        input [31:0] dw11;
        input [31:0] dw12;
        begin
            @(posedge clk); #0.2;
            host_cmd_valid = 1'b1;
            host_cmd_dw0   = {cid, 8'd0, opcode};
            host_cmd_dw1   = nsid;
            host_cmd_dw10  = dw10;
            host_cmd_dw11  = dw11;
            host_cmd_dw12  = dw12;
            @(posedge clk); #0.2;
            host_cmd_valid = 1'b0;
        end
    endtask

    task ring_doorbell;
        input [7:0]  db_addr;
        input [15:0] db_val;
        begin
            @(posedge clk); #0.2;
            host_db_wr_en = 1'b1;
            host_db_addr  = db_addr;
            host_db_val   = db_val;
            @(posedge clk); #0.2;
            host_db_wr_en = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("sim/waves/tb_nvme_ssd_controller.vcd");
        $dumpvars(0, tb_nvme_ssd_controller);

        clk                  = 0;
        rst_n                = 0;
        host_db_wr_en        = 0;
        host_db_addr         = 8'd0;
        host_db_val          = 16'd0;
        host_cmd_valid       = 0;
        host_cmd_dw0         = 32'd0;
        host_cmd_dw1         = 32'd0;
        host_cmd_dw10        = 32'd0;
        host_cmd_dw11        = 32'd0;
        host_cmd_dw12        = 32'd0;
        host_ecc_enc_start   = 0;
        host_ecc_enc_data    = 64'd0;
        host_ecc_enc_valid   = 0;
        host_ecc_dec_start   = 0;
        host_ecc_dec_data    = 64'd0;
        host_ecc_dec_valid   = 0;
        host_ecc_dec_parity  = 64'd0;
        host_erase_req       = 0;
        host_erase_block_idx = 10'd0;

        for (c = 0; c < CHANNELS; c = c + 1) begin
            nand_dq_in[c*8 +: 8] = 8'h5A;
        end

        $display("=====================================================================");
        $display("   ENTERPRISE NVME PCIE GEN3 SSD CONTROLLER ASIC VERIFICATION SUITE  ");
        $display("=====================================================================");

        // -------------------------------------------------------------
        // Test 1: Power-on Reset & Interface Idle State
        // -------------------------------------------------------------
        #20;
        rst_n = 1;
        #10;

        if (host_cmd_ready && !host_cqe_valid && !host_msix_irq &&
            (nand_ce_n == {CHANNELS{1'b1}}) && !status_gc_needed &&
            (status_max_erase_count == 16'd0)) begin
            $display("[PASS] Test 1: Power-on Reset verified across host, NAND, and FTL ports.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 1: Unexpected reset state.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 2: NVMe Identify Controller & Namespace Admin Command
        // -------------------------------------------------------------
        saw_host_cqe = 0;
        saw_msix_irq = 0;
        submit_nvme_cmd(16'h0001, 8'h06, 32'h00000001, 32'h00000001, 32'd0, 32'd0);
        repeat(5) @(posedge clk);

        if (saw_host_cqe && host_cqe_data[111:96] == 16'h0001 && host_cqe_data[112] == 1'b1) begin
            $display("[PASS] Test 2: NVMe Identify Controller Admin command completed with valid CQE.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 2: Identify Admin command failed (CID=%h).", host_cqe_data[111:96]);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 3: I/O Submission Queue (SQ) and Completion Queue (CQ) Creation
        // -------------------------------------------------------------
        saw_host_cqe = 0;
        submit_nvme_cmd(16'h0002, 8'h05, 32'd0, {16'd64, 16'd1}, 32'd0, 32'd0);
        repeat(5) @(posedge clk);
        submit_nvme_cmd(16'h0003, 8'h01, 32'd0, {16'd64, 16'd1}, 32'd0, 32'd0);
        repeat(5) @(posedge clk);

        if (saw_host_cqe && host_cqe_data[111:96] == 16'h0003) begin
            $display("[PASS] Test 3: I/O Submission & Completion Queues created successfully.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 3: Queue creation failed (CID=%h).", host_cqe_data[111:96]);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 4: NVMe Write Command Submission & Doorbell Ring
        // -------------------------------------------------------------
        ring_doorbell(8'h02, 16'd1); // SQ 1 Doorbell offset 2 -> Tail=1
        repeat(2) @(posedge clk);
        if (status_cmd_pending == 1'b1) begin
            $display("[PASS] Test 4: Host Doorbell write registered; Queue Arbiter flagged pending SQ work.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 4: Doorbell arbiter did not signal pending command.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 5: Hardware FTL Logical-to-Physical Address (LBA -> NAND Channel 5)
        // -------------------------------------------------------------
        saw_host_cqe   = 0;
        saw_msix_irq   = 0;
        saw_ch5_ce     = 0;
        saw_dqs_toggle = 0;
        submit_nvme_cmd(16'h0010, 8'h01, 32'h00000001, 32'h00000005, 32'd0, 32'd0); // Write LBA 5
        repeat(6) @(posedge clk);

        if (saw_ch5_ce && (nand_ce_n[5] == 1'b0 || saw_dqs_toggle)) begin
            $display("[PASS] Test 5: Hardware FTL routed LBA 5 cleanly to physical NAND Channel 5.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 5: Expected Channel 5 CE# activation on LBA 5 write (ce_n=%b).", nand_ce_n);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 6: BCH ECC Encoder Parity Generation (External Host Port)
        // -------------------------------------------------------------
        @(posedge clk); #0.2;
        host_ecc_enc_start = 1'b1;
        @(posedge clk); #0.2;
        host_ecc_enc_start      = 1'b0;
        host_ecc_enc_valid = 1'b1;
        begin: bch_enc_loop
            integer w;
            for (w = 0; w < 16; w = w + 1) begin
                host_ecc_enc_data = 64'h0123456789ABCDEF + w;
                @(posedge clk); #0.2;
            end
        end
        host_ecc_enc_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (saw_ecc_enc_done && latched_enc_parity != 64'd0) begin
            $display("[PASS] Test 6: BCH ECC Engine generated 64-bit Galois Field parity: %016h",
                latched_enc_parity);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 6: BCH ECC parity generation failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 7: Multi-Channel Toggle NAND Flash Page Program Completion
        // -------------------------------------------------------------
        repeat(15) @(posedge clk);

        if (saw_dqs_toggle && (nand_ce_n == {CHANNELS{1'b1}})) begin
            $display("[PASS] Test 7: Toggle NAND Page Program completed with DDR DQS strobe and released CE#.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 7: NAND Page Program sequence incomplete (dqs=%b ce_n=%b).",
                saw_dqs_toggle, nand_ce_n);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 8: BCH Error Correction of Non-LSB Bit Flip (Bit 37)
        // -------------------------------------------------------------
        @(posedge clk); #0.2;
        host_ecc_dec_start  = 1'b1;
        saw_ecc_dec_done    = 1'b0;
        @(posedge clk); #0.2;
        host_ecc_dec_start  = 1'b0;
        host_ecc_dec_parity = latched_enc_parity;
        host_ecc_dec_valid  = 1'b1;
        begin: bch_dec_loop
            integer w;
            for (w = 0; w < 16; w = w + 1) begin
                if (w == 15)
                    host_ecc_dec_data = (64'h0123456789ABCDEF + w) ^ 64'h0000002000000000; // Flip bit 37
                else
                    host_ecc_dec_data = 64'h0123456789ABCDEF + w;
                @(posedge clk); #0.2;
            end
        end
        host_ecc_dec_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (saw_ecc_dec_done && latched_dec_errors == 5'd1 && !latched_dec_uncorr &&
            latched_dec_corrected == (64'h0123456789ABCDEF + 15)) begin
            $display("[PASS] Test 8: BCH Decoder located and corrected bit-37 memory flip successfully.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 8: BCH Error Correction failed (done=%b err=%d uncorr=%b data=%016h).",
                saw_ecc_dec_done, latched_dec_errors, latched_dec_uncorr, latched_dec_corrected);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 9: Wear-Leveling Block Erase Tracking & GC Trigger
        // -------------------------------------------------------------
        begin: erase_loop
            integer e;
            for (e = 0; e < 55; e = e + 1) begin
                @(posedge clk); #0.2;
                host_erase_req       = 1'b1;
                host_erase_block_idx = 10'd5;
                @(posedge clk); #0.2;
                host_erase_req       = 1'b0;
            end
        end
        repeat(5) @(posedge clk);

        if (status_max_erase_count >= 16'd55 && status_gc_needed) begin
            $display("[PASS] Test 9: Wear-leveling tracked block erase count (%0d) and triggered GC.",
                status_max_erase_count);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 9: Wear leveling trigger failed (max=%d, gc=%b).",
                status_max_erase_count, status_gc_needed);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 10: NVMe Completion Queue Entry (CQE) Posting & Host IRQ Assertion
        // -------------------------------------------------------------
        if (saw_host_cqe && saw_msix_irq && host_cqe_data[111:96] == 16'h0010) begin
            $display("[PASS] Test 10: NVMe Write CQE (CID=0x0010) posted via DMA with Host MSI-X IRQ.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 10: CQE post or MSI-X IRQ assertion failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test Summary and Sign-off
        // -------------------------------------------------------------
        $display("=====================================================================");
        $display("   TEST SUMMARY: PASSED %0d / 10 TESTS", tests_passed);
        $display("=====================================================================");

        if (tests_passed == 10 && tests_failed == 0) begin
            $display(">>> ALL 10 VERIFICATION TESTS COMPLETED WITH 100%% PASS RATE <<<");
            $finish;
        end else begin
            $display(">>> VERIFICATION FAILED WITH %0d FAILURES <<<", tests_failed);
            $fatal(1, "Testbench execution terminated with errors.");
        end
    end

endmodule
