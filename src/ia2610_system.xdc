################################################################################
# Device
#set_property CFGBVS GND                        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true    [current_design]

################################################################################
# Physical

set_property PACKAGE_PIN AG10 [get_ports drv_ain1]
set_property PACKAGE_PIN AF11 [get_ports drv_ain2]
set_property PACKAGE_PIN AH12 [get_ports drv_bin1]
set_property PACKAGE_PIN AE10 [get_ports drv_bin2]
set_property IOSTANDARD LVCMOS33 [get_ports {drv_*}]
set_property DRIVE 4 [get_ports {drv_*}]
set_property SLEW SLOW [get_ports {drv_*}]

# CMOS Sensor
# LVCMOS pins
set_property PACKAGE_PIN AD11 [get_ports cam_rstn]
set_property PACKAGE_PIN AB11 [get_ports cam_sck]
set_property PACKAGE_PIN AB10 [get_ports cam_ss_n]
set_property PACKAGE_PIN AD10 [get_ports cam_mosi]
set_property PACKAGE_PIN AC11 [get_ports cam_miso]
set_property PACKAGE_PIN AA8  [get_ports {cam_trigger[0]}]
set_property PACKAGE_PIN AA10 [get_ports {cam_trigger[1]}]
set_property PACKAGE_PIN AB9  [get_ports {cam_trigger[2]}]
set_property PACKAGE_PIN AA11 [get_ports {cam_monitor[0]}]
set_property PACKAGE_PIN Y9   [get_ports {cam_monitor[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {cam_rstn}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_sck}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_ss_n}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_mosi}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_miso}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_trigger*}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_monitor*}]

set_property DRIVE 4 [get_ports {cam_rstn}]
set_property DRIVE 4 [get_ports {cam_sck}]
set_property DRIVE 4 [get_ports {cam_ss_n}]
set_property DRIVE 4 [get_ports {cam_mosi}]
set_property DRIVE 4 [get_ports {cam_miso}]
set_property DRIVE 4 [get_ports {cam_trigger*}]
set_property DRIVE 4 [get_ports {cam_monitor*}]

set_property SLEW SLOW [get_ports {cam_rstn}]
set_property SLEW SLOW [get_ports {cam_sck}]
set_property SLEW SLOW [get_ports {cam_ss_n}]
set_property SLEW SLOW [get_ports {cam_mosi}]
set_property SLEW SLOW [get_ports {cam_miso}]
set_property SLEW SLOW [get_ports {cam_trigger*}]
set_property SLEW SLOW [get_ports {cam_monitor*}]

# LVDS pins
set_property PACKAGE_PIN U9   [get_ports {cam_clkin_p}]
set_property PACKAGE_PIN K4   [get_ports {cam_clkout_p}]
set_property PACKAGE_PIN R8   [get_ports {cam_sync_p}]
set_property PACKAGE_PIN J7   [get_ports {cam_dout_p[0]}]
set_property PACKAGE_PIN J6   [get_ports {cam_dout_p[1]}]
set_property PACKAGE_PIN K8   [get_ports {cam_dout_p[2]}]
set_property PACKAGE_PIN M8   [get_ports {cam_dout_p[3]}]
set_property PACKAGE_PIN L3   [get_ports {cam_dout_p[4]}]
set_property PACKAGE_PIN L1   [get_ports {cam_dout_p[5]}]
set_property PACKAGE_PIN N7   [get_ports {cam_dout_p[6]}]
set_property PACKAGE_PIN N9   [get_ports {cam_dout_p[7]}]

set_property IOSTANDARD LVDS [get_ports {cam_clk*}]
set_property IOSTANDARD LVDS [get_ports {cam_sync*}]
set_property IOSTANDARD LVDS [get_ports {cam_dout*}]

set_property DIFF_TERM TRUE [get_ports {cam_clkout*}]
set_property DIFF_TERM TRUE [get_ports {cam_sync*}]
set_property DIFF_TERM TRUE [get_ports {cam_dout*}]

# Clock pins
set_property PACKAGE_PIN AC12 [get_ports {pl_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {pl_clk}]

#create_clock -name pl_clk -period 40.000 [get_ports {pl_clk}];

# MISC.
# Debug clock
set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets {soc_i/CLK_100m_out}]

################################################################################
# Timing

# Clock constraints for internal clock mode
create_generated_clock -name serdes_clk [get_pins {clk_gen_0/clk_i/CLKOUT0}];
create_generated_clock -name serdes_clkdiv [get_pins {clk_gen_0/clk_i/CLKOUT1}];
create_generated_clock -name idlyctrl_clk [get_pins {clk_gen_0/clk_i/CLKOUT2}];

#set_clock_group \
#    -group {clk_pl_0 clk_pl_1 clk_pl_2 clk_pl_3} \
#    -group {serdes_clk serdes_clkdiv idlyctrl_clk} \
#    -asynchronous

# Clock constraints for external clock mode using CLKOUT
#set CLKOUT_PERIOD 3.333
#create_clock -name cam_clk -period $CLKOUT_PERIOD [get_ports {cam_clkout_p}];
#create_generated_clock -name cam_sclk [get_pins -hier -filter {NAME=~python_if_0/*/CLKOUT0}];
#create_generated_clock -name cam_clkdiv [get_pins -hier -filter {NAME=~python_if_0/*/CLKOUT1}];
#create_generated_clock -name cam_clkdiv2 [get_pins -hier -filter {NAME=~python_if_0/*/CLKOUT2}];

#set_clock_group \
#    -group {clk_pl_0 clk_pl_1 clk_pl_2 clk_pl_3} \
#    -group {cam_sclk cam_clkdiv cam_clkdiv2} \
#    -asynchronous

# DDR input delay
set_input_delay -clock cam_clk -max [expr $CLKOUT_PERIOD/2 + 0.1] [get_ports {cam_dout_* cam_sync_*}]
set_input_delay -clock cam_clk -min [expr $CLKOUT_PERIOD/2 - 0.1] [get_ports {cam_dout_* cam_sync_*}]
set_input_delay -clock cam_clk -max [expr $CLKOUT_PERIOD/2 + 0.1] [get_ports {cam_dout_* cam_sync_*}] -clock_fall -add_delay
set_input_delay -clock cam_clk -min [expr $CLKOUT_PERIOD/2 - 0.1] [get_ports {cam_dout_* cam_sync_*}] -clock_fall -add_delay

