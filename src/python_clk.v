module python_clk #(
    parameter CLK_DEVICE = "MMCM"
) (
    input reset,  // clock reset
    input clk_in, // input clock from serdes output
    output clk_out, // output clock phase aligned
    output clk_div, // iserdes clock
    output clk_div2, // parallel clock
    output locked
);

wire clkfb;
wire clkout0;
wire clkout1;
wire clkout2;
wire clkout3;
wire clkout4;
wire clkout5;
wire clkout6;

BUFG clkout0_bufg_i (.I(clkout0),    .O(clk_out));
BUFG clkout1_bufg_i (.I(clkout1),    .O(clk_div));
BUFG clkout2_bufg_i (.I(clkout2),    .O(clk_div2));

generate

if (CLK_DEVICE == "MMCM") begin
MMCME2_ADV #(
    .BANDWIDTH            ("OPTIMIZED"),
    .COMPENSATION         ("ZHOLD"),
    .DIVCLK_DIVIDE        (1),
    .CLKFBOUT_MULT_F      (4.000),      // VCO=1200MHz
    .CLKFBOUT_PHASE       (45.0),
    .CLKFBOUT_USE_FINE_PS ("FALSE"),
    .CLKOUT0_DIVIDE_F     (4),        // 1200/4=300MHz
    .CLKOUT1_DIVIDE       (16),          // 1200/16=75Mhz
    .CLKOUT2_DIVIDE       (20),          // 1200/20=60Mhz
    .CLKIN1_PERIOD        (3.333333)       // 300MHz
)
mmcm_i
(
    .CLKFBOUT            (clkfb),
    .CLKOUT0             (clkout0),
    .CLKOUT1             (clkout1),
    .CLKOUT2             (clkout2),
    .CLKOUT3             (clkout3),
    .CLKOUT4             (clkout4),
    .CLKOUT5             (clkout5),
    .CLKOUT6             (clkout6),
     // Input clock control
    .CLKFBIN             (clkfb),
    .CLKIN1              (clk_in),
    .CLKIN2              (1'b0),
     // Tied to always select the primary input clock
    .CLKINSEL            (1'b1),
    // Ports for dynamic reconfiguration
    .DADDR               (7'h0),
    .DCLK                (1'b0),
    .DEN                 (1'b0),
    .DI                  (16'h0),
    .DO                  (),
    .DRDY                (),
    .DWE                 (1'b0),
    // Ports for dynamic phase shift
    .PSCLK               (1'b0),
    .PSEN                (1'b0),
    .PSINCDEC            (1'b0),
    .PSDONE              (),
    // Other control and status signals
    .LOCKED              (locked),
    .CLKINSTOPPED        (),
    .CLKFBSTOPPED        (),
    .PWRDWN              (1'b0),
    .RST                 (reset)
);
end
else if (CLK_DEVICE == "PLL") begin
PLLE2_ADV #(
    .BANDWIDTH            ("OPTIMIZED"),
    .COMPENSATION         ("ZHOLD"),
    .DIVCLK_DIVIDE        (1),
    .CLKFBOUT_MULT        (4),      // VCO=1200MHz
    .CLKFBOUT_PHASE       (45.0),
    .CLKOUT0_DIVIDE       (4),        // 1200/4=300MHz
    .CLKOUT1_DIVIDE       (16),          // 1200/16=75Mhz
    .CLKOUT2_DIVIDE       (20),          // 1200/20=60Mhz
    .CLKIN1_PERIOD        (3.333333)       // 300MHz
)
pll_i
(
    .CLKFBOUT            (clkfb),
    .CLKOUT0             (clkout0),
    .CLKOUT1             (clkout1),
    .CLKOUT2             (clkout2),
    .CLKOUT3             (clkout3),
    .CLKOUT4             (clkout4),
    .CLKOUT5             (clkout5),
     // Input clock control
    .CLKFBIN             (clkfb),
    .CLKIN1              (clk_in),
    .CLKIN2              (1'b0),
     // Tied to always select the primary input clock
    .CLKINSEL            (1'b1),
    // Ports for dynamic reconfiguration
    .DADDR               (7'h0),
    .DCLK                (1'b0),
    .DEN                 (1'b0),
    .DI                  (16'h0),
    .DO                  (),
    .DRDY                (),
    .DWE                 (1'b0),
    // Other control and status signals
    .LOCKED              (locked),
    .PWRDWN              (1'b0),
    .RST                 (reset)
);
end

endgenerate

endmodule
