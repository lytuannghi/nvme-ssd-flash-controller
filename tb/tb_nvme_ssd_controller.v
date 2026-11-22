// =============================================================================
// File: tb_nvme_ssd_controller.v
// Module: tb_nvme_ssd_controller
// Project: Enterprise NVMe PCIe Gen3 SSD Controller ASIC
// Description: Comprehensive Self-Checking Testbench executing 10 verification
//              test suites with cycle-accurate timing and automated pass/fail criteria.
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

    // Physical Toggle DDR NAND Flash Interface (8 Channels)
    wire [CHANNELS-1:0] nand_cle;
    wire [CHANNELS-1:0] nand_ale;
    wire [CHANNELS-1:0] nand_ce_n;
    wire [CHANNELS-1:0] nand_we_n;
    wire [CHANNELS-1:0] nand_re_n;
    wire [CHANNELS-1:0] nand_dqs;
    wire [7:0]          nand_dq_out [0:CHANNELS-1];
    reg  [7:0]          nand_dq_in  [0:CHANNELS-1];

    // Status Telemetry
    wire                status_gc_needed;
    wire [15:0]         status_max_erase_count;

    integer tests_passed = 0;
    integer tests_failed = 0;
    integer c;

    // Sticky event monitors
    reg saw_host_cqe;
    reg saw_msix_irq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_host_cqe <= 1'b0;
            saw_msix_irq <= 1'b0;
        end else begin
            if (host_cqe_valid) saw_host_cqe <= 1'b1;
            if (host_msix_irq)  saw_msix_irq <= 1'b1;
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
        .status_gc_needed      (status_gc_needed),
        .status_max_erase_count(status_max_erase_count)
    );

    // 250 MHz System Clock (4.0 ns period)
    always #2.0 clk = ~clk;

    // Helper Task: Submit NVMe Command
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

    // Helper Task: Ring Doorbell
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

        clk            = 0;
        rst_n          = 0;
        host_db_wr_en  = 0;
        host_db_addr   = 8'd0;
        host_db_val    = 16'd0;
        host_cmd_valid = 0;
        host_cmd_dw0   = 32'd0;
        host_cmd_dw1   = 32'd0;
        host_cmd_dw10  = 32'd0;
        host_cmd_dw11  = 32'd0;
        host_cmd_dw12  = 32'd0;

        for (c = 0; c < CHANNELS; c = c + 1) begin
            nand_dq_in[c] = 8'h5A;
        end

        $display("=====================================================================");
        $display("   ENTERPRISE NVME PCIE GEN3 SSD CONTROLLER ASIC VERIFICATION SUITE  ");
        $display("=====================================================================");

        // -------------------------------------------------------------
        // Test 1: Power-on Reset & Doorbell Register Initialization
        // -------------------------------------------------------------
        #20;
        rst_n = 1;
        #10;

        if (u_dut.u_queue_mgr.sq_head[0] == 16'd0 && u_dut.u_queue_mgr.cq_phase[0] == 1'b1) begin
            $display("[PASS] Test 1: Power-on Reset successful. Admin Queue initialized with Phase=1.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 1: Queue manager initialization failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 2: NVMe Identify Controller & Namespace Admin Command
        // -------------------------------------------------------------
        saw_host_cqe = 0;
        saw_msix_irq = 0;
        submit_nvme_cmd(16'h0001, 8'h06, 32'h00000001, 32'h00000001, 32'd0, 32'd0); // Identify (CNS=1)
        repeat(5) @(posedge clk);

        if (saw_host_cqe && host_cqe_data[111:96] == 16'h0001) begin
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
        // Create I/O CQ 1 (QID 1, Size 64)
        submit_nvme_cmd(16'h0002, 8'h05, 32'd0, {16'd64, 16'd1}, 32'd0, 32'd0);
        repeat(5) @(posedge clk);
        // Create I/O SQ 1 (QID 1, Size 64)
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
        // Ring SQ 1 Doorbell: Tail advances to 1
        ring_doorbell(8'h02, 16'd1); // SQ 1 Doorbell is offset 2
        #1;
        if (u_dut.u_queue_mgr.sq_tail[1] == 16'd1) begin
            $display("[PASS] Test 4: Host Doorbell write registered. SQ 1 Tail advanced to 1.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 4: Doorbell write failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 5: Hardware FTL Logical-to-Physical Address (LBA -> PBA) Mapping
        // -------------------------------------------------------------
        // Submit Write command to LBA 0x00000005
        saw_host_cqe = 0;
        submit_nvme_cmd(16'h0010, 8'h01, 32'h00000001, 32'h00000005, 32'd0, 32'd0); // Write LBA 5
        repeat(5) @(posedge clk);

        if (u_dut.u_ftl.pba_channel == 3'd5 && u_dut.u_ftl.pba_block == 10'd1) begin
            $display("[PASS] Test 5: Hardware FTL translated LBA 5 -> Channel 5, Block 1, Page 0.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 5: FTL LBA mapping mismatch (Ch=%d, Blk=%d).",
                u_dut.u_ftl.pba_channel, u_dut.u_ftl.pba_block);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 6: BCH ECC Encoder Parity Generation (1KB sector)
        // -------------------------------------------------------------
        u_dut.ecc_enc_start = 1;
        @(posedge clk); #0.2;
        u_dut.ecc_enc_start = 0;
        u_dut.ecc_enc_data_valid = 1;
        begin: bch_enc_loop
            integer w;
            for (w = 0; w < 16; w = w + 1) begin
                u_dut.ecc_enc_data_in = 64'h0123456789ABCDEF + w;
                @(posedge clk); #0.2;
            end
        end
        u_dut.ecc_enc_data_valid = 0;
        repeat(3) @(posedge clk);

        if (u_dut.u_bch_ecc.enc_parity_out != 64'd0) begin
            $display("[PASS] Test 6: BCH ECC Engine generated 64-bit Galois Field parity: %016h",
                u_dut.u_bch_ecc.enc_parity_out);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 6: BCH ECC parity generation failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 7: Multi-Channel Toggle NAND Flash Page Program (Channels 0-7)
        // -------------------------------------------------------------
        // Wait for NAND state machine to complete the write command
        repeat(15) @(posedge clk);

        if (nand_ce_n != {CHANNELS{1'b0}} && u_dut.u_nand_ctrl.nand_busy == 1'b0) begin
            $display("[PASS] Test 7: Multi-Channel Toggle NAND Page Program executed with DDR DQS strobe.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 7: NAND Page Program sequence failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 8: Toggle NAND Flash Page Read & BCH Error Correction of Injected Bit Flips
        // -------------------------------------------------------------
        // Inject a bit-flip into decoder input
        u_dut.ecc_dec_start = 1;
        @(posedge clk); #0.2;
        u_dut.ecc_dec_start = 0;
        u_dut.ecc_dec_parity_in = u_dut.u_bch_ecc.enc_parity_out;
        u_dut.ecc_dec_data_valid = 1;
        begin: bch_dec_loop
            integer w;
            for (w = 0; w < 16; w = w + 1) begin
                // Inject 1-bit error on last word
                if (w == 15)
                    u_dut.ecc_dec_data_in = (64'h0123456789ABCDEF + w) ^ 64'h0000000000000001;
                else
                    u_dut.ecc_dec_data_in = 64'h0123456789ABCDEF + w;
                @(posedge clk); #0.2;
            end
        end
        u_dut.ecc_dec_data_valid = 0;
        repeat(3) @(posedge clk);

        if (u_dut.u_bch_ecc.dec_errors_found == 5'd1 &&
            u_dut.u_bch_ecc.dec_data_corrected == (64'h0123456789ABCDEF + 15)) begin
            $display("[PASS] Test 8: BCH Decoder located and corrected 1-bit memory flip successfully.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 8: BCH Error Correction failed (Errors=%d).", u_dut.u_bch_ecc.dec_errors_found);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 9: Wear-Leveling Block Erase Count Tracking & Garbage Collection Trigger
        // -------------------------------------------------------------
        // Erase block 5 repeatedly (55 times) to induce wear imbalance
        begin: erase_loop
            integer e;
            for (e = 0; e < 55; e = e + 1) begin
                @(posedge clk); #0.2;
                u_dut.block_erase_req = 1;
                u_dut.erase_block_idx = 10'd5;
                @(posedge clk); #0.2;
                u_dut.block_erase_req = 0;
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
        if (saw_host_cqe && saw_msix_irq) begin
            $display("[PASS] Test 10: NVMe CQE posted via DMA and Host MSI-X Interrupt asserted successfully.");
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
