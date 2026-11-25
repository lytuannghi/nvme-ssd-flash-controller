// =============================================================================
// File: nvme_ssd_controller_top.v
// Module: nvme_ssd_controller_top
// Project: Enterprise NVMe PCIe Gen3 SSD Controller ASIC
// Description: Top-Level SoC Integration of NVMe Controller:
//              - PCIe Host Command Ingestion & NVMe 64-byte Command Parser
//              - Multi-Queue Arbiter & Hardware Doorbell Manager
//              - Hardware Flash Translation Layer (FTL) & Wear-Leveling
//              - Galois Field BCH ECC Encoder / Decoder
//              - 8-Channel Toggle DDR NAND Flash Controller (Verilog-2005 packed)
// =============================================================================

`timescale 1ns / 1ps

module nvme_ssd_controller_top #(
    parameter CHANNELS = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Host Doorbell Register Interface
    input  wire                  host_db_wr_en,
    input  wire [7:0]            host_db_addr,
    input  wire [15:0]           host_db_val,

    // Host Command Ingestion Interface
    input  wire                  host_cmd_valid,
    input  wire [31:0]           host_cmd_dw0,
    input  wire [31:0]           host_cmd_dw1,
    input  wire [31:0]           host_cmd_dw10,
    input  wire [31:0]           host_cmd_dw11,
    input  wire [31:0]           host_cmd_dw12,
    output wire                  host_cmd_ready,

    // Host Completion Queue DMA Interface
    output wire                  host_cqe_valid,
    output wire [127:0]          host_cqe_data,
    output wire                  host_msix_irq,

    // Physical Toggle DDR NAND Flash Interface (8 Channels, Packed)
    output wire [CHANNELS-1:0]   nand_cle,
    output wire [CHANNELS-1:0]   nand_ale,
    output wire [CHANNELS-1:0]   nand_ce_n,
    output wire [CHANNELS-1:0]   nand_we_n,
    output wire [CHANNELS-1:0]   nand_re_n,
    output wire [CHANNELS-1:0]   nand_dqs,
    output wire [CHANNELS*8-1:0] nand_dq_out,
    input  wire [CHANNELS*8-1:0] nand_dq_in,

    // Host BCH ECC Control & Data Interface
    input  wire                  host_ecc_enc_start,
    input  wire [63:0]           host_ecc_enc_data,
    input  wire                  host_ecc_enc_valid,
    output wire                  host_ecc_enc_done,
    output wire [63:0]           host_ecc_enc_parity,
    input  wire                  host_ecc_dec_start,
    input  wire [63:0]           host_ecc_dec_data,
    input  wire                  host_ecc_dec_valid,
    input  wire [63:0]           host_ecc_dec_parity,
    output wire                  host_ecc_dec_done,
    output wire [63:0]           host_ecc_dec_corrected,
    output wire [4:0]            host_ecc_dec_errors,
    output wire                  host_ecc_dec_uncorr,

    // Host FTL Maintenance Interface
    input  wire                  host_erase_req,
    input  wire [9:0]            host_erase_block_idx,

    // Controller Status Telemetry
    output wire                  status_cmd_pending,
    output wire                  status_gc_needed,
    output wire [15:0]           status_max_erase_count
);

    // =========================================================================
    // 1. NVMe Command Parser
    // =========================================================================
    wire [15:0] parsed_cid;
    wire [7:0]  parsed_opcode;
    wire [31:0] parsed_nsid;
    wire [63:0] parsed_slba;
    wire [15:0] parsed_nlb;
    wire [15:0] parsed_qid;
    wire [15:0] parsed_qsize;
    wire        parsed_is_admin;
    wire        parsed_is_write;
    wire        parsed_is_read;
    wire        parsed_is_identify;
    wire        parsed_is_create_q;
    wire        cmd_parsed_pulse;

    nvme_admin_cmd_parser u_cmd_parser (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid      (host_cmd_valid),
        .cmd_dw0        (host_cmd_dw0),
        .cmd_dw1        (host_cmd_dw1),
        .cmd_dw10       (host_cmd_dw10),
        .cmd_dw11       (host_cmd_dw11),
        .cmd_dw12       (host_cmd_dw12),
        .cmd_ready      (host_cmd_ready),
        .out_cmd_id     (parsed_cid),
        .out_opcode     (parsed_opcode),
        .out_nsid       (parsed_nsid),
        .out_slba       (parsed_slba),
        .out_nlb        (parsed_nlb),
        .out_qid        (parsed_qid),
        .out_qsize      (parsed_qsize),
        .out_is_admin   (parsed_is_admin),
        .out_is_write   (parsed_is_write),
        .out_is_read    (parsed_is_read),
        .out_is_identify(parsed_is_identify),
        .out_is_create_q(parsed_is_create_q),
        .out_cmd_parsed (cmd_parsed_pulse)
    );

    // =========================================================================
    // 2. Hardware Queue Manager & Doorbell Controller
    // =========================================================================
    wire        sq_cmd_avail;
    wire [3:0]  fetch_qid;
    wire [15:0] fetch_sq_head;
    reg         post_cqe_en;
    reg  [3:0]  post_cqid;
    reg  [15:0] post_cid;
    reg  [15:0] post_status;

    assign status_cmd_pending = sq_cmd_avail;

    nvme_queue_manager #(
        .NUM_QUEUES(8),
        .QUEUE_DEPTH(64)
    ) u_queue_mgr (
        .clk          (clk),
        .rst_n        (rst_n),
        .db_wr_en     (host_db_wr_en),
        .db_addr      (host_db_addr),
        .db_val       (host_db_val),
        .sq_cmd_avail (sq_cmd_avail),
        .fetch_qid    (fetch_qid),
        .fetch_sq_head(fetch_sq_head),
        .sq_cmd_ack   (cmd_parsed_pulse),
        .post_cqe_en  (post_cqe_en),
        .post_cqid    (post_cqid),
        .post_cid     (post_cid),
        .post_status  (post_status),
        .cqe_dma_valid(host_cqe_valid),
        .cqe_dma_data (host_cqe_data),
        .host_irq     (host_msix_irq)
    );

    // =========================================================================
    // 3. Hardware Flash Translation Layer (FTL)
    // =========================================================================
    wire        ftl_lookup_done;
    wire [2:0]  pba_channel;
    wire [1:0]  pba_die;
    wire [9:0]  pba_block;
    wire [7:0]  pba_page;
    wire        erase_ack;
    wire [15:0] min_erase_count;

    flash_translation_layer #(
        .NUM_LBAS(256),
        .NUM_BLOCKS(64)
    ) u_ftl (
        .clk            (clk),
        .rst_n          (rst_n),
        .lookup_req     (cmd_parsed_pulse && (parsed_is_write || parsed_is_read)),
        .lookup_lba     (parsed_slba[31:0]),
        .lookup_is_write(parsed_is_write),
        .lookup_done    (ftl_lookup_done),
        .pba_channel    (pba_channel),
        .pba_die        (pba_die),
        .pba_block      (pba_block),
        .pba_page       (pba_page),
        .block_erase_req(host_erase_req),
        .erase_block_idx(host_erase_block_idx),
        .erase_ack      (erase_ack),
        .max_erase_count(status_max_erase_count),
        .min_erase_count(min_erase_count),
        .gc_needed      (status_gc_needed)
    );

    // =========================================================================
    // 4. Hardware BCH ECC Engine
    // =========================================================================
    bch_ecc_engine u_bch_ecc (
        .clk               (clk),
        .rst_n             (rst_n),
        .enc_start         (host_ecc_enc_start),
        .enc_data_in       (host_ecc_enc_data),
        .enc_data_valid    (host_ecc_enc_valid),
        .enc_done          (host_ecc_enc_done),
        .enc_parity_out    (host_ecc_enc_parity),
        .dec_start         (host_ecc_dec_start),
        .dec_data_in       (host_ecc_dec_data),
        .dec_data_valid    (host_ecc_dec_valid),
        .dec_parity_in     (host_ecc_dec_parity),
        .dec_done          (host_ecc_dec_done),
        .dec_data_corrected(host_ecc_dec_corrected),
        .dec_errors_found  (host_ecc_dec_errors),
        .dec_uncorrectable (host_ecc_dec_uncorr)
    );

    // =========================================================================
    // 5. 8-Channel Toggle DDR NAND Flash Controller
    // =========================================================================
    reg         nand_cmd_valid;
    reg  [2:0]  nand_channel_sel;
    reg  [1:0]  nand_op;
    reg  [9:0]  nand_block_reg;
    reg  [7:0]  nand_page_reg;
    reg  [63:0] nand_wr_data_reg;
    wire        nand_busy;
    wire        nand_done;
    wire [63:0] nand_rd_data;

    toggle_nand_channel_controller #(
        .CHANNELS(CHANNELS)
    ) u_nand_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .nand_cmd_valid  (nand_cmd_valid),
        .nand_channel_sel(nand_channel_sel),
        .nand_op         (nand_op),
        .nand_block      (nand_block_reg),
        .nand_page       (nand_page_reg),
        .nand_wr_data    (nand_wr_data_reg),
        .nand_busy       (nand_busy),
        .nand_done       (nand_done),
        .nand_rd_data    (nand_rd_data),
        .nand_cle        (nand_cle),
        .nand_ale        (nand_ale),
        .nand_ce_n       (nand_ce_n),
        .nand_we_n       (nand_we_n),
        .nand_re_n       (nand_re_n),
        .nand_dqs        (nand_dqs),
        .nand_dq_out     (nand_dq_out),
        .nand_dq_in      (nand_dq_in)
    );

    // =========================================================================
    // 6. Central Execution Orchestrator
    // =========================================================================
    localparam STATE_IDLE      = 3'd0;
    localparam STATE_FTL_WAIT  = 3'd1;
    localparam STATE_NAND_WAIT = 3'd2;
    localparam STATE_POST_CQE  = 3'd3;

    reg [2:0] exec_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exec_state       <= STATE_IDLE;
            post_cqe_en      <= 1'b0;
            post_cqid        <= 4'd0;
            post_cid         <= 16'd0;
            post_status      <= 16'd0;
            nand_cmd_valid   <= 1'b0;
            nand_channel_sel <= 3'd0;
            nand_op          <= 2'd0;
            nand_block_reg   <= 10'd0;
            nand_page_reg    <= 8'd0;
            nand_wr_data_reg <= 64'd0;
        end else begin
            post_cqe_en    <= 1'b0;
            nand_cmd_valid <= 1'b0;

            case (exec_state)
                STATE_IDLE: begin
                    if (cmd_parsed_pulse) begin
                        if (parsed_is_admin) begin
                            post_cqe_en <= 1'b1;
                            post_cqid   <= 4'd0;
                            post_cid    <= parsed_cid;
                            post_status <= 16'h0000;
                        end else if (parsed_is_write || parsed_is_read) begin
                            exec_state <= STATE_FTL_WAIT;
                        end
                    end
                end

                STATE_FTL_WAIT: begin
                    if (ftl_lookup_done) begin
                        nand_cmd_valid   <= 1'b1;
                        nand_channel_sel <= pba_channel;
                        nand_op          <= parsed_is_write ? 2'd1 : 2'd0;
                        nand_block_reg   <= pba_block;
                        nand_page_reg    <= pba_page;
                        nand_wr_data_reg <= 64'hFEDCBA9876543210;
                        exec_state       <= STATE_NAND_WAIT;
                    end
                end

                STATE_NAND_WAIT: begin
                    if (nand_done) begin
                        exec_state <= STATE_POST_CQE;
                    end
                end

                STATE_POST_CQE: begin
                    post_cqe_en <= 1'b1;
                    post_cqid   <= 4'd1;
                    post_cid    <= parsed_cid;
                    post_status <= 16'h0000;
                    exec_state  <= STATE_IDLE;
                end

                default: exec_state <= STATE_IDLE;
            endcase
        end
    end

endmodule
