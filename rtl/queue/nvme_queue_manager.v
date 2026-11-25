// =============================================================================
// File: nvme_queue_manager.v
// Module: nvme_queue_manager
// Project: Enterprise NVMe PCIe Gen3 SSD Controller ASIC
// Description: Multi-Queue Hardware Doorbell, Arbiter & Queue Manager.
//              - Manages Admin Queue (QID 0) and up to 8 I/O Submission/Completion Queues.
//              - Round-Robin SQ fetching arbiter.
//              - Generates 16-byte NVMe Completion Queue Entries (CQE).
//              - Phase bit toggling and Host Interrupt (MSI-X) assertion.
// =============================================================================

`timescale 1ns / 1ps

module nvme_queue_manager #(
    parameter NUM_QUEUES = 8,
    parameter QUEUE_DEPTH = 64
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Host Doorbell Register Write Interface
    input  wire                 db_wr_en,
    input  wire [7:0]           db_addr,       // Offset: 2*QID for SQ, 2*QID+1 for CQ
    input  wire [15:0]          db_val,        // New Tail (for SQ) or new Head (for CQ)

    // Controller Command Fetch Interface
    output reg                  sq_cmd_avail,
    output reg  [3:0]           fetch_qid,
    output reg  [15:0]          fetch_sq_head,
    input  wire                 sq_cmd_ack,

    // Controller Completion Post Interface
    input  wire                 post_cqe_en,
    input  wire [3:0]           post_cqid,
    input  wire [15:0]          post_cid,
    input  wire [15:0]          post_status,   // NVMe Status Code (0x0000 = Success)

    // CQE Output to Host Memory DMA
    output reg                  cqe_dma_valid,
    output reg  [127:0]         cqe_dma_data,  // 16-byte CQ Entry
    output reg                  host_irq       // Host MSI-X Interrupt pulse
);

    // Submission Queue State Arrays
    reg [15:0] sq_head [0:NUM_QUEUES-1];
    reg [15:0] sq_tail [0:NUM_QUEUES-1];
    reg        sq_active [0:NUM_QUEUES-1];

    // Completion Queue State Arrays
    reg [15:0] cq_head [0:NUM_QUEUES-1];
    reg [15:0] cq_tail [0:NUM_QUEUES-1];
    reg        cq_phase [0:NUM_QUEUES-1];
    reg        cq_active [0:NUM_QUEUES-1];

    integer i;

    // Doorbell Processing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_QUEUES; i = i + 1) begin
                sq_head[i]   <= 16'd0;
                sq_tail[i]   <= 16'd0;
                sq_active[i] <= (i == 0) ? 1'b1 : 1'b0; // Admin SQ active by default

                cq_head[i]   <= 16'd0;
                cq_tail[i]   <= 16'd0;
                cq_phase[i]  <= 1'b1;                   // Phase bit starts at 1
                cq_active[i] <= (i == 0) ? 1'b1 : 1'b0; // Admin CQ active by default
            end
        end else if (db_wr_en) begin
            if (db_addr[0] == 1'b0) begin
                // SQ Doorbell: Host updates SQ Tail
                if (db_addr[4:1] < NUM_QUEUES) begin
                    sq_tail[db_addr[4:1]]   <= db_val;
                    sq_active[db_addr[4:1]] <= 1'b1;
                end
            end else begin
                // CQ Doorbell: Host updates CQ Head
                if (db_addr[4:1] < NUM_QUEUES) begin
                    cq_head[db_addr[4:1]] <= db_val;
                end
            end
        end
    end

    // Round-Robin Submission Queue Fetch Arbiter
    reg [3:0] rr_ptr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sq_cmd_avail  <= 1'b0;
            fetch_qid     <= 4'd0;
            fetch_sq_head <= 16'd0;
            rr_ptr        <= 4'd0;
        end else begin
            if (sq_cmd_ack) begin
                // Acknowledge fetch, increment SQ head
                sq_head[fetch_qid] <= (sq_head[fetch_qid] == QUEUE_DEPTH - 1) ? 16'd0 : (sq_head[fetch_qid] + 16'd1);
                sq_cmd_avail       <= 1'b0;
                rr_ptr             <= (rr_ptr == NUM_QUEUES - 1) ? 4'd0 : (rr_ptr + 4'd1);
            end else if (!sq_cmd_avail) begin
                // Search next active queue with pending commands
                for (i = 0; i < NUM_QUEUES; i = i + 1) begin
                    if (!sq_cmd_avail && sq_active[i] && (sq_head[i] != sq_tail[i])) begin
                        sq_cmd_avail  <= 1'b1;
                        fetch_qid     <= i[3:0];
                        fetch_sq_head <= sq_head[i];
                    end
                end
            end
        end
    end

    // CQE Generation and IRQ Assertion
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cqe_dma_valid <= 1'b0;
            cqe_dma_data  <= 128'd0;
            host_irq      <= 1'b0;
        end else begin
            cqe_dma_valid <= 1'b0;
            host_irq      <= 1'b0;

            if (post_cqe_en && (post_cqid < NUM_QUEUES)) begin
                cqe_dma_valid <= 1'b1;
                // Construct standard 16-byte CQE:
                // Dword 0: Command-specific result (0)
                // Dword 1: Reserved (0)
                // Dword 2: SQ Head Pointer [31:16], SQ ID [15:0]
                // Dword 3: Status Field [31:17], Phase Tag [16], Command ID [15:0]
                cqe_dma_data <= {
                    post_status[14:0], cq_phase[post_cqid], post_cid, // Dword 3
                    sq_head[post_cqid], {12'd0, post_cqid},           // Dword 2
                    32'd0,                                            // Dword 1
                    32'd0                                             // Dword 0
                };

                // Advance CQ Tail & toggle phase on wrap-around
                if (cq_tail[post_cqid] == QUEUE_DEPTH - 1) begin
                    cq_tail[post_cqid]  <= 16'd0;
                    cq_phase[post_cqid] <= ~cq_phase[post_cqid];
                end else begin
                    cq_tail[post_cqid] <= cq_tail[post_cqid] + 16'd1;
                end

                host_irq <= 1'b1;
            end
        end
    end

endmodule
