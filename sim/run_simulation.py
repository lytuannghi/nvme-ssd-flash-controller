#!/usr/bin/env python3
"""
Automated Simulation Runner for NVMe SSD Flash Controller ASIC
Runs Icarus Verilog compilation and VVP execution, verifying 10/10 testbench assertions.
"""

import subprocess
import os
import sys

def main():
    proj_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(proj_dir)

    os.makedirs("sim/waves", exist_ok=True)
    vvp_out = os.path.join("sim", "nvme_sim.vvp")

    # Source files list
    sources = [
        "rtl/nvme/nvme_admin_cmd_parser.v",
        "rtl/queue/nvme_queue_manager.v",
        "rtl/ecc/bch_ecc_engine.v",
        "rtl/ftl/flash_translation_layer.v",
        "rtl/nand_ctrl/toggle_nand_channel_controller.v",
        "rtl/nvme_ssd_controller_top.v",
        "tb/tb_nvme_ssd_controller.v"
    ]

    print("[INFO] Compiling Enterprise NVMe SSD Controller ASIC RTL and Testbench...")
    compile_cmd = ["iverilog", "-g2012", "-o", vvp_out] + sources
    res = subprocess.run(compile_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("[ERROR] Compilation failed:")
        print(res.stderr)
        sys.exit(1)
    print("[INFO] Compilation successful!")

    print("[INFO] Running VVP simulation...")
    run_cmd = ["vvp", vvp_out]
    sim_res = subprocess.run(run_cmd, capture_output=True, text=True)
    print(sim_res.stdout)
    if sim_res.returncode != 0 or "ALL 10 VERIFICATION TESTS COMPLETED WITH 100% PASS RATE" not in sim_res.stdout:
        print("[FAILURE] Simulation failed assertion checks.")
        sys.exit(1)

    print("[SUCCESS] All 10 Enterprise NVMe SSD Controller test cases PASSED!")

if __name__ == "__main__":
    main()
