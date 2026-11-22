#!/usr/bin/env python3
"""
ASIC Physical Layout Generator (GDSII Stream Format)
Design: Enterprise NVMe PCIe Gen3 SSD Controller ASIC
Process: TSMC 28nm HPC+ CMOS
Dimensions: 1550 um x 1550 um
"""

import struct
import os

def create_gds_record(rec_type, data_type, data_bytes=b""):
    rec_length = len(data_bytes) + 4
    header = struct.pack(">HH", rec_length, (rec_type << 8) | data_type)
    return header + data_bytes

def create_boundary(layer, datatype, coords):
    res = bytearray()
    res += create_gds_record(0x08, 0x00) # BOUNDARY
    res += create_gds_record(0x0D, 0x02, struct.pack(">h", layer))
    res += create_gds_record(0x0E, 0x02, struct.pack(">h", datatype))
    coord_bytes = bytearray()
    for x, y in coords:
        coord_bytes += struct.pack(">ii", int(x), int(y))
    coord_bytes += struct.pack(">ii", int(coords[0][0]), int(coords[0][1]))
    res += create_gds_record(0x10, 0x03, coord_bytes) # XY
    res += create_gds_record(0x11, 0x00) # ENDEL
    return res

def create_box(layer, datatype, x1, y1, x2, y2):
    return create_boundary(layer, datatype, [(x1, y1), (x2, y1), (x2, y2), (x1, y2)])

def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "gds")
    os.makedirs(out_dir, exist_ok=True)
    gds_path = os.path.join(out_dir, "nvme_ssd_controller_top.gds")

    stream = bytearray()
    # HEADER
    stream += create_gds_record(0x00, 0x02, struct.pack(">h", 600))
    # BGNLIB
    stream += create_gds_record(0x01, 0x02, struct.pack(">12h", 2026, 11, 22, 12, 0, 0, 2026, 11, 22, 12, 0, 0))
    # LIBNAME
    lib_name = b"NVME_SSD_CONTROLLER_LIB\0"
    if len(lib_name) % 2 != 0: lib_name += b"\0"
    stream += create_gds_record(0x02, 0x06, lib_name)
    # UNITS (0.001 um database unit = 1 nm)
    stream += create_gds_record(0x03, 0x05, struct.pack(">dd", 0.001, 1e-9))

    # BGNSTR
    stream += create_gds_record(0x05, 0x02, struct.pack(">12h", 2026, 11, 22, 12, 0, 0, 2026, 11, 22, 12, 0, 0))
    # STRNAME
    cell_name = b"nvme_ssd_controller_top\0"
    if len(cell_name) % 2 != 0: cell_name += b"\0"
    stream += create_gds_record(0x06, 0x06, cell_name)

    # 1. Chip Sealring & Boundary: 1550um x 1550um
    stream += create_box(100, 0, 0, 0, 1550000, 1550000)
    stream += create_box(100, 1, 25000, 25000, 1525000, 1525000)

    # 2. IO Pad Ring (Outer perimeter: PCIe differential pads, NAND Flash pads)
    for i in range(14):
        pos = 65000 + i * 105000
        stream += create_box(105, 0, pos, 30000, pos + 70000, 105000)      # Bottom Pads
        stream += create_box(105, 0, pos, 1445000, pos + 70000, 1520000) # Top Pads
        stream += create_box(105, 0, 30000, pos, 105000, pos + 70000)      # Left Pads
        stream += create_box(105, 0, 1445000, pos, 1520000, pos + 70000) # Right Pads

    # 3. Core Logic Floorplan Blocks
    # u_cmd_parser: PCIe Ingestion & Command Parser
    stream += create_box(30, 0, 150000, 150000, 480000, 450000)
    # u_queue_mgr: Multi-Queue Arbiter & Doorbell Registers
    stream += create_box(31, 0, 520000, 150000, 950000, 450000)
    # u_ftl: Flash Translation Layer & Mapping RAM Macro
    stream += create_box(32, 0, 150000, 500000, 700000, 950000)
    stream += create_box(33, 0, 200000, 540000, 650000, 900000) # FTL L2P Table SRAM
    # u_bch_ecc: Galois Field BCH ECC Encoder / Decoder
    stream += create_box(34, 0, 750000, 500000, 1400000, 950000)
    # u_nand_ctrl: 8-Channel Toggle DDR NAND Controller & Data Buffers
    stream += create_box(35, 0, 150000, 1000000, 1400000, 1400000)
    # 8 Channel Toggle PHY Interface Blocks
    for ch in range(8):
        ch_pos = 180000 + ch * 145000
        stream += create_box(36, 0, ch_pos, 1040000, ch_pos + 120000, 1360000)

    # 4. Power Grid Network (VDD / VSS Straps in Metal 8 & Metal 9)
    for p in range(160000, 1400000, 90000):
        stream += create_box(48, 0, p, 130000, p + 14000, 1420000)      # M8 VDD/VSS Vertical Straps
        stream += create_box(49, 0, 130000, p, 1420000, p + 14000)      # M9 VDD/VSS Horizontal Straps

    # ENDSTR
    stream += create_gds_record(0x07, 0x00)
    # ENDLIB
    stream += create_gds_record(0x04, 0x00)

    with open(gds_path, "wb") as f:
        f.write(stream)

    print(f"[INFO] GDSII physical layout generated successfully: {gds_path} ({len(stream)} bytes)")

if __name__ == "__main__":
    main()
