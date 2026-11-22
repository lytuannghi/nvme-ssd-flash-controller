# ==============================================================================
# Design Compiler Synthesis Script
# Design: nvme_ssd_controller_top
# Target Library: TSMC 28nm HPC+ 0.9V Low-Power Logic Standard Cells
# ==============================================================================

set DESIGN_NAME "nvme_ssd_controller_top"

set_app_var search_path ". ./rtl ./rtl/nvme ./rtl/queue ./rtl/ecc ./rtl/ftl ./rtl/nand_ctrl /tools/synopsys/libs"
set_app_var target_library "tcbn28hpcplus_ss0p9v125c.db"
set_app_var link_library "* tcbn28hpcplus_ss0p9v125c.db tcbn28hpcplus_ff0p99v0c.db"

# Analyze Verilog RTL Sources
analyze -format verilog {
    ./rtl/nvme/nvme_admin_cmd_parser.v
    ./rtl/queue/nvme_queue_manager.v
    ./rtl/ecc/bch_ecc_engine.v
    ./rtl/ftl/flash_translation_layer.v
    ./rtl/nand_ctrl/toggle_nand_channel_controller.v
    ./rtl/nvme_ssd_controller_top.v
}

# Elaborate Top-Level Module
elaborate $DESIGN_NAME

# Apply Timing Constraints
source ./syn/nvme_timing.sdc

# Check Unresolved References and Constraints
check_design > ./syn/reports/check_design.rpt
check_timing > ./syn/reports/check_timing.rpt

# Compile and Map Logic
compile_ultra -gate_clock -scan

# Generate Reports
report_timing -delay_type max -max_paths 10 > ./syn/reports/timing_report.txt
report_timing -delay_type min -max_paths 10 >> ./syn/reports/timing_report.txt
report_area -hierarchy > ./syn/reports/area_report.txt
report_power -hierarchy > ./syn/reports/power_report.txt
report_qor > ./syn/reports/qor_report.txt

# Export Synthesized Gate-Level Netlist and Constraints
write -format verilog -hierarchy -output ./syn/netlist/nvme_ssd_controller_top_syn.v
write_sdc ./syn/netlist/nvme_ssd_controller_top_syn.sdc

puts "[INFO] Synthesis completed successfully for $DESIGN_NAME."
