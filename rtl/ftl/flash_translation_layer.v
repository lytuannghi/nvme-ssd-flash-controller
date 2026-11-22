// =============================================================================
// File: flash_translation_layer.v
// Module: flash_translation_layer
// Project: Enterprise NVMe PCIe Gen3 SSD Controller ASIC
// Description: Hardware Flash Translation Layer (FTL) & Wear-Leveling Engine.
//              - LBA to PBA (Channel, Die, Block, Page) address translation.
//              - Wear-leveling: Tracks erase cycles per physical block.
//              - Free-block allocation and Garbage Collection (GC) trigger.
// =============================================================================

`timescale 1ns / 1ps

module flash_translation_layer #(
    parameter NUM_LBAS   = 256,
    parameter NUM_BLOCKS = 64
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Address Lookup Interface
    input  wire                 lookup_req,
    input  wire [31:0]          lookup_lba,
    input  wire                 lookup_is_write,
    output reg                  lookup_done,
    output reg  [2:0]           pba_channel,
    output reg  [1:0]           pba_die,
    output reg  [9:0]           pba_block,
    output reg  [7:0]           pba_page,

    // Block Erase & Wear Leveling Interface
    input  wire                 block_erase_req,
    input  wire [9:0]           erase_block_idx,
    output reg                  erase_ack,
    output reg  [15:0]          max_erase_count,
    output reg  [15:0]          min_erase_count,
    output reg                  gc_needed       // Garbage Collection Trigger flag
);

    // LBA-to-PBA Translation Mapping RAM: [Channel(3), Die(2), Block(10), Page(8)] = 23 bits
    reg [22:0] mapping_table [0:NUM_LBAS-1];

    // Wear-Leveling Erase Count Table (16-bit count per physical block)
    reg [15:0] erase_counters [0:NUM_BLOCKS-1];

    // Free block allocation pointer
    reg [9:0] free_block_ptr;
    reg [7:0] current_page_ptr;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookup_done      <= 1'b0;
            pba_channel      <= 3'd0;
            pba_die          <= 2'd0;
            pba_block        <= 10'd0;
            pba_page         <= 8'd0;
            erase_ack        <= 1'b0;
            max_erase_count  <= 16'd0;
            min_erase_count  <= 16'd0;
            gc_needed        <= 1'b0;
            free_block_ptr   <= 10'd1;
            current_page_ptr <= 8'd0;

            for (i = 0; i < NUM_LBAS; i = i + 1) begin
                // Initial 1:1 mapping: Channel = LBA[2:0], Die = LBA[4:3], Block = LBA[7:5], Page = 0
                mapping_table[i] <= {i[2:0], i[4:3], 5'd0, i[7:5], 8'd0};
            end
            for (i = 0; i < NUM_BLOCKS; i = i + 1) begin
                erase_counters[i] <= 16'd0;
            end
        end else begin
            lookup_done <= 1'b0;
            erase_ack   <= 1'b0;

            // Handle LBA Lookup / Allocation
            if (lookup_req) begin
                lookup_done <= 1'b1;
                if (lookup_is_write) begin
                    // Out-of-place write: Allocate new physical page
                    pba_channel <= lookup_lba[2:0]; // Striping across 8 NAND channels
                    pba_die     <= lookup_lba[4:3];
                    pba_block   <= free_block_ptr;
                    pba_page    <= current_page_ptr;

                    // Update mapping table entry
                    mapping_table[lookup_lba[7:0]] <= {lookup_lba[2:0], lookup_lba[4:3], free_block_ptr, current_page_ptr};

                    // Advance page pointer
                    if (current_page_ptr == 8'd127) begin
                        current_page_ptr <= 8'd0;
                        free_block_ptr   <= (free_block_ptr == NUM_BLOCKS - 1) ? 10'd1 : free_block_ptr + 10'd1;
                    end else begin
                        current_page_ptr <= current_page_ptr + 8'd1;
                    end
                end else begin
                    // Read operation: Retrieve mapped PBA
                    pba_channel <= mapping_table[lookup_lba[7:0]][22:20];
                    pba_die     <= mapping_table[lookup_lba[7:0]][19:18];
                    pba_block   <= mapping_table[lookup_lba[7:0]][17:8];
                    pba_page    <= mapping_table[lookup_lba[7:0]][7:0];
                end
            end

            // Handle Physical Block Erase & Wear Leveling
            if (block_erase_req && (erase_block_idx < NUM_BLOCKS)) begin
                erase_ack <= 1'b1;
                erase_counters[erase_block_idx] <= erase_counters[erase_block_idx] + 16'd1;

                if (erase_counters[erase_block_idx] + 16'd1 > max_erase_count)
                    max_erase_count <= erase_counters[erase_block_idx] + 16'd1;

                // Check wear discrepancy between max and min erase counts
                if ((max_erase_count - min_erase_count) > 16'd50) begin
                    gc_needed <= 1'b1; // Trigger wear-leveling GC
                end
            end
        end
    end

endmodule
