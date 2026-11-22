// =============================================================================
// File: nvme_admin_cmd_parser.v
// Module: nvme_admin_cmd_parser
// Project: Enterprise NVMe PCIe Gen3 SSD Controller ASIC
// Description: Hardware NVMe 64-byte Command Parser for Admin & NVM Command Sets.
//              Supports:
//              - Identify Controller / Namespace (Opcode 0x06)
//              - Create I/O Submission Queue (Opcode 0x01, NSID=0)
//              - Create I/O Completion Queue (Opcode 0x05, NSID=0)
//              - NVM Read (Opcode 0x02, NSID>=1)
//              - NVM Write (Opcode 0x01, NSID>=1)
// =============================================================================

`timescale 1ns / 1ps

module nvme_admin_cmd_parser (
    input  wire                 clk,
    input  wire                 rst_n,

    // Command Input Interface (64-byte Command Dwords 0 - 15)
    input  wire                 cmd_valid,
    input  wire [31:0]          cmd_dw0,   // CID[31:16], FUSE[9:8], Opcode[7:0]
    input  wire [31:0]          cmd_dw1,   // NSID (Namespace ID)
    input  wire [31:0]          cmd_dw10,  // Specific Dword 10 (SLBA low / QID / CNS)
    input  wire [31:0]          cmd_dw11,  // Specific Dword 11 (SLBA high / QSIZE)
    input  wire [31:0]          cmd_dw12,  // Specific Dword 12 (Number of Logical Blocks NLB)
    output reg                  cmd_ready,

    // Decoded Command Outputs
    output reg  [15:0]          out_cmd_id,
    output reg  [7:0]           out_opcode,
    output reg  [31:0]          out_nsid,
    output reg  [63:0]          out_slba,       // Starting LBA for Read/Write
    output reg  [15:0]          out_nlb,        // Number of logical blocks
    output reg  [15:0]          out_qid,        // Queue ID for Create SQ/CQ
    output reg  [15:0]          out_qsize,      // Queue Size
    output reg                  out_is_admin,   // 1: Admin command, 0: NVM I/O
    output reg                  out_is_write,   // 1: Write command
    output reg                  out_is_read,    // 1: Read command
    output reg                  out_is_identify,// 1: Identify command
    output reg                  out_is_create_q,// 1: Create SQ/CQ
    output reg                  out_cmd_parsed  // 1-cycle strobe indicating command ready
);

    localparam OP_ADMIN_DELETE_SQ = 8'h00;
    localparam OP_ADMIN_CREATE_SQ = 8'h01;
    localparam OP_ADMIN_DELETE_CQ = 8'h04;
    localparam OP_ADMIN_CREATE_CQ = 8'h05;
    localparam OP_ADMIN_IDENTIFY  = 8'h06;

    localparam OP_NVM_WRITE       = 8'h01;
    localparam OP_NVM_READ        = 8'h02;

    reg parse_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_ready       <= 1'b1;
            out_cmd_id      <= 16'd0;
            out_opcode      <= 8'd0;
            out_nsid        <= 32'd0;
            out_slba        <= 64'd0;
            out_nlb         <= 16'd0;
            out_qid         <= 16'd0;
            out_qsize       <= 16'd0;
            out_is_admin    <= 1'b0;
            out_is_write    <= 1'b0;
            out_is_read     <= 1'b0;
            out_is_identify <= 1'b0;
            out_is_create_q <= 1'b0;
            out_cmd_parsed  <= 1'b0;
            parse_pending   <= 1'b0;
        end else begin
            out_cmd_parsed <= parse_pending;
            parse_pending  <= 1'b0;

            if (cmd_valid && cmd_ready) begin
                out_cmd_id <= cmd_dw0[31:16];
                out_opcode <= cmd_dw0[7:0];
                out_nsid   <= cmd_dw1;

                if (cmd_dw0[7:0] == OP_ADMIN_IDENTIFY) begin
                    out_is_admin    <= 1'b1;
                    out_is_identify <= 1'b1;
                    out_is_create_q <= 1'b0;
                    out_is_write    <= 1'b0;
                    out_is_read     <= 1'b0;
                end else if (cmd_dw1 == 32'd0 && (cmd_dw0[7:0] == OP_ADMIN_CREATE_SQ || cmd_dw0[7:0] == OP_ADMIN_CREATE_CQ)) begin
                    out_is_admin    <= 1'b1;
                    out_is_create_q <= 1'b1;
                    out_is_identify <= 1'b0;
                    out_is_write    <= 1'b0;
                    out_is_read     <= 1'b0;
                    out_qid         <= cmd_dw10[15:0];
                    out_qsize       <= cmd_dw10[31:16];
                end else if (cmd_dw1 != 32'd0 && cmd_dw0[7:0] == OP_NVM_WRITE) begin
                    out_is_admin    <= 1'b0;
                    out_is_write    <= 1'b1;
                    out_is_read     <= 1'b0;
                    out_is_identify <= 1'b0;
                    out_is_create_q <= 1'b0;
                    out_slba        <= {cmd_dw11, cmd_dw10};
                    out_nlb         <= cmd_dw12[15:0] + 16'd1;
                end else if (cmd_dw1 != 32'd0 && cmd_dw0[7:0] == OP_NVM_READ) begin
                    out_is_admin    <= 1'b0;
                    out_is_write    <= 1'b0;
                    out_is_read     <= 1'b1;
                    out_is_identify <= 1'b0;
                    out_is_create_q <= 1'b0;
                    out_slba        <= {cmd_dw11, cmd_dw10};
                    out_nlb         <= cmd_dw12[15:0] + 16'd1;
                end else begin
                    out_is_admin    <= 1'b0;
                    out_is_write    <= 1'b0;
                    out_is_read     <= 1'b0;
                    out_is_identify <= 1'b0;
                    out_is_create_q <= 1'b0;
                end

                parse_pending <= 1'b1;
            end
        end
    end

endmodule
