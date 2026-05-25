# ====================================================================
# Xilinx Design Constraints (XDC) for Artix-7 Platforms
# Project: RIS FPGA Controller Architecture
# Target Device: XC7A35T-CSG324-1
# ====================================================================

# 1. Clock Timing Constraints (100 MHz Onboard Crystal Oscillator)
create_clock -period 10.000 -name clk_in [get_ports clk_in]

# 2. Pin Location Constraints (Example standard Artix-7 CSG324 pin mapping)

# Onboard 100 MHz Single-Ended Clock Pin
set_property -dict { PACKAGE_PIN W5    IOSTANDARD LVCMOS33 } [get_ports clk_in]

# Active-low Reset Pin (User Button)
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports rst_n]

# 3. Output Shift Register Interface Pins (Routed to Pmod/Expansion Header)
# Configuration: Fast Slew rate and 12 mA Drive Strength to drive physical diode shift registers
set_property -dict { PACKAGE_PIN A14   IOSTANDARD LVCMOS33   SLEW FAST   DRIVE 12 } [get_ports ris_sclk]
set_property -dict { PACKAGE_PIN A16   IOSTANDARD LVCMOS33   SLEW FAST   DRIVE 12 } [get_ports ris_sdata]
set_property -dict { PACKAGE_PIN B15   IOSTANDARD LVCMOS33   SLEW FAST   DRIVE 12 } [get_ports ris_latch]

# Status Pin (Onboard LED)
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33   SLEW SLOW   DRIVE 8  } [get_ports busy]
