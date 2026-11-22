# ==============================================================================
# Synopsys Design Constraints (SDC)
# Design: nvme_ssd_controller_top
# Operating Frequency: 250 MHz (Clock Period = 4.000 ns)
# Process: TSMC 28nm HPC+ Logic Library
# ==============================================================================

# Primary Master Clock Definition (250 MHz)
create_clock -name clk -period 4.000 -waveform {0.000 2.000} [get_ports clk]

# Clock Uncertainty and Jitter Constraints
set_clock_uncertainty -setup 0.150 [get_clocks clk]
set_clock_uncertainty -hold  0.080 [get_clocks clk]
set_clock_transition 0.050 [get_clocks clk]

# Input Port Delay Constraints
set_input_delay -clock clk -max 0.800 [get_ports {rst_n host_db_* host_cmd_* nand_dq_in*}]
set_input_delay -clock clk -min 0.200 [get_ports {rst_n host_db_* host_cmd_* nand_dq_in*}]

# Output Port Delay Constraints
set_output_delay -clock clk -max 0.900 [get_ports {host_cmd_ready host_cqe_* host_msix_irq nand_cle* nand_ale* nand_ce_n* nand_we_n* nand_re_n* nand_dqs* nand_dq_out* status_*}]
set_output_delay -clock clk -min 0.150 [get_ports {host_cmd_ready host_cqe_* host_msix_irq nand_cle* nand_ale* nand_ce_n* nand_we_n* nand_re_n* nand_dqs* nand_dq_out* status_*}]

# Drive Strength and Output Load Modeling
set_driving_cell -lib_cell INVD2BWP -library tcbn28hpcplus_ss0p9v125c [all_inputs]
set_load 0.025 [all_outputs]

# Multicycle Path & False Path Constraints
set_false_path -from [get_ports rst_n]
