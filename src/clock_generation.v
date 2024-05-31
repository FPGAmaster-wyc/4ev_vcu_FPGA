module clock_generation(
    input   reset,
    input   refclk,

    output  serdes_clk,
    output  serdes_clkdiv,
    output  idlyctrl_clk,
    output  locked
);

wire clkfb;
wire clkout0;
wire clkout1;
wire clkout2;
wire clkout3;
wire clkout4;
wire clkout5;
wire clkout6;

BUFG clkout0_bufg_i (.I(clkout0),    .O(serdes_clk));
BUFG clkout1_bufg_i (.I(clkout1),    .O(serdes_clkdiv));
BUFG clkout2_bufg_i (.I(clkout2),    .O(idlyctrl_clk));

MMCME2_ADV #(
    .BANDWIDTH            ("OPTIMIZED"),
    .COMPENSATION         ("ZHOLD"),
    .DIVCLK_DIVIDE        (1),
    .CLKFBOUT_MULT_F      (12.000),      // VCO=800MHz
    .CLKFBOUT_USE_FINE_PS ("FALSE"),
    .CLKOUT0_DIVIDE_F     (4),        // 1200/4=300MHz
    .CLKOUT1_DIVIDE       (16),          // 1200/16=75Mhz
    .CLKOUT2_DIVIDE       (4),          // 1200/4=300Mhz
    .CLKIN1_PERIOD        (10.000)       // 100MHz
)
mmcm_0
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
    .CLKIN1              (refclk),
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

endmodule

