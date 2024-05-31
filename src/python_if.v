////////////////////////////////////////////////////////////////////////////////
// Interface module to ONSEMI PYTHON series sensors
//
//
module python_if #(
    parameter PIXEL_BITS=10,
    parameter FS=10'h2AA, // frame start
    parameter LS=10'h0AA, // line start
    parameter BS=10'h22A, // blank start
    parameter FE=10'h3AA, // frame end
    parameter LE=10'h12A, // line end
    parameter BLK=10'h015, // blank pixel
    parameter IMG=10'h035, // valid pixel
    parameter CRC=10'h059, // CRC
    parameter TR=10'h3A6, // training pattern
    parameter CH=4, // LVDS channels
    parameter WIDTH_BITS=12, // horizontal counter bits
    parameter HEIGHT_BITS=12, // vertical counter bits
    parameter USE_CLKOUT="TRUE", // use CLKOUT as clock source
    parameter CLK_DEVICE="MMCM", // use MMCM or PLL for clock generation
    parameter USE_IDELAY="FALSE", // use IDELAY for phase align
    parameter IDLY_REFCLK_FREQ=300.0, // IDELAY_CTRL clock frequency
    parameter AUTO_RETRAIN="FALSE", // re-train between frames
    parameter MIN_PHASE_WINDOW=200, // about 500ps
    parameter DEBUG="FALSE"
)(
    input reset,

    // reference clock for idelay
    input idlyctrl_clk,
    // optional internal clocks if USE_CLKOUT="FALSE"
    input clk_serdes, // serial clock
    input clk_div, // serdes clock
    input clk_div2, // pixel clock

    // sensor LVDS signals
    // optional sensor input clock. drived by clk_serdes
    output clkin_p,
    output clkin_n,
    // sensor output clock
    input clkout_p,
    input clkout_n,
    // sync channel
    input sync_p,
    input sync_n,
    // data channels
    input [CH-1:0] dout_p,
    input [CH-1:0] dout_n,

    // rx enable
    input enable,
    // subsample mode, see datasheet
    input subsample,
    // status
    output serdes_ready,
    output training_done,

    // parallel data
    output pclk,
    output [CH*PIXEL_BITS-1:0] pdata,
    output fvalid,
    output lvalid,
    output black,
    output sof,
    output eof,
    output sol,
    output eol,
    output [WIDTH_BITS-1:0] hsize,
    output [HEIGHT_BITS-1:0] vsize
);

wire clkout; // serial clock, DDR
wire clkdiv; // iserdes clock
wire clkdiv2; // parallel clock

wire clkout_i;
IBUFDS clkout_ibufds_i(.I(clkout_p), .IB(clkout_n), .O(clkout_i));
OBUFDS clkin_obufds_i(.I(clk_serdes), .O(clkin_p), .OB(clkin_n));

generate
if(USE_CLKOUT=="TRUE") begin
    // use clkout_p/n input, this is the default
    // use a MMCM in "ZHOLD" mode to align clock with data input
    python_clk #(.CLK_DEVICE(CLK_DEVICE)) clk_gen_i(
        .reset(!enable),
        .clk_in(clkout_i),
        .clk_out(clkout),
        .clk_div(clkdiv),
        .clk_div2(clkdiv2)
    );
end
else begin
    // use internal clock
    // in this mode sensor should bypass pll and use lvds clock input
    assign clkout = clk_serdes;
    assign clkdiv = clk_div;
end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Auto re-train to calibrate temperature drift
wire training_request;
generate
if(AUTO_RETRAIN=="TRUE") begin
    reg training_request_r;
    always @(posedge pclk, posedge reset)
    begin
        if(reset) begin
            training_request_r <= 0;
        end
        else begin
            // issue a training sequence after every frame
            training_request_r <= eof;
        end
    end
    assign training_request = training_request_r;
end
else begin
    assign training_request = 0;
end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// LVDS serdes
wire [CH:0] dbg_lane_locked;
wire [(CH+1)*9-1:0] dbg_lane_phase;
wire [(CH+1)*5-1:0] dbg_lane_bitpos;
wire [CH:0] dbg_lane_wordpos;

assign serdes_ready = &dbg_lane_locked;

wire [CH*PIXEL_BITS-1:0] pdout;
wire [PIXEL_BITS-1:0] psync;

wire serdes_enable = enable && !training_request;

// FIXME: image pipeline is 10bit but the core only supports 8bit currently.
// sensor has to be configured as 8bit.
wire [CH*8-1:0] pdout_8b;
wire [7:0] psync_8b;
wire [7:0] TR_8b = TR[PIXEL_BITS-1:PIXEL_BITS-8];
lvds_rx_top #(
    .LANES(CH+1),
    .DATA_BITS(8),
    .FIRST_BIT("MSB"),
    .MIN_PHASE_WINDOW(MIN_PHASE_WINDOW),
    .USE_IDELAY(USE_IDELAY),
    .IDLY_REFCLK_FREQ(IDLY_REFCLK_FREQ)
)serdes_0(
    .reset(reset),
    .training_pattern({(CH+1){TR_8b}}),
    .idlyctrl_clk(idlyctrl_clk),
    .clkin(clkout),
    .clkdiv(clkdiv),
    .clkdiv2(clkdiv),
    .data_p({sync_p, dout_p}),
    .data_n({sync_n, dout_n}),
    .enable(serdes_enable),
    .training_done(training_done),
    .training_vtz(),
    .training_sync(),
    .clkout(pclk),
    .dataout({psync_8b, pdout_8b}),
    .dbg_lane_locked(dbg_lane_locked),
    .dbg_lane_phase(dbg_lane_phase),
    .dbg_lane_bitpos(dbg_lane_bitpos),
    .dbg_lane_wordpos(dbg_lane_wordpos)
);
// padding with 01 to emulate 10bit mode
assign psync = {psync_8b,2'b10};
assign pdout = {
        pdout_8b[8*7+7:8*7],2'b10,
        pdout_8b[8*6+7:8*6],2'b10,
        pdout_8b[8*5+7:8*5],2'b10,
        pdout_8b[8*4+7:8*4],2'b10,
        pdout_8b[8*3+7:8*3],2'b10,
        pdout_8b[8*2+7:8*2],2'b10,
        pdout_8b[8*1+7:8*1],2'b10,
        pdout_8b[8*0+7:8*0],2'b10
    };

////////////////////////////////////////////////////////////////////////////////
// data format decoder
wire lvalid_a;
python_decode #(
    .PIXEL_BITS(PIXEL_BITS),
    .FS(FS),
    .LS(LS),
    .BS(BS),
    .FE(FE),
    .LE(LE),
    .BLK(BLK),
    .IMG(IMG),
    .CRC(CRC),
    .TR(TR),
    .CH(CH),
    .WIDTH_BITS(WIDTH_BITS),
    .HEIGHT_BITS(HEIGHT_BITS)
)dec_0(
    .rst(!serdes_ready),
    .clk(pclk),
    .mode(subsample),
    .din(pdout),
    .sync(psync),
    .pdata(pdata),
    .fvalid(fvalid),
    .lvalid(lvalid_a),
    .black(black),
    .sof(sof),
    .eof(eof),
    .sol(sol),
    .eol(eol),
    .hsize(hsize),
    .vsize(vsize)
);

assign lvalid = lvalid_a && training_done;

generate
if (DEBUG == "TRUE") begin:DBG
    if(USE_IDELAY == "TRUE") begin
    python_if_vio vio_0(
        .clk(pclk),
        .probe_in0(dbg_lane_phase[9*0+8:9*0]),
        .probe_in1(dbg_lane_phase[9*1+8:9*1]),
        .probe_in2(dbg_lane_phase[9*2+8:9*2]),
        .probe_in3(dbg_lane_phase[9*3+8:9*3]),
        .probe_in4(dbg_lane_phase[9*4+8:9*4]),
        .probe_in5(dbg_lane_phase[9*5+8:9*5]),
        .probe_in6(dbg_lane_phase[9*6+8:9*6]),
        .probe_in7(dbg_lane_phase[9*7+8:9*7]),
        .probe_in8(dbg_lane_phase[9*8+8:9*8]),
        .probe_in9(dbg_lane_bitpos[5*0+4:5*0]),
        .probe_in10(dbg_lane_bitpos[5*1+4:5*1]),
        .probe_in11(dbg_lane_bitpos[5*2+4:5*2]),
        .probe_in12(dbg_lane_bitpos[5*3+4:5*3]),
        .probe_in13(dbg_lane_bitpos[5*4+4:5*4]),
        .probe_in14(dbg_lane_bitpos[5*5+4:5*5]),
        .probe_in15(dbg_lane_bitpos[5*6+4:5*6]),
        .probe_in16(dbg_lane_bitpos[5*7+4:5*7]),
        .probe_in17(dbg_lane_bitpos[5*8+4:5*8])
    );
    end
    ila_144 ila_1(
        .clk(pclk),
        .probe0({
            dbg_lane_wordpos,
            dbg_lane_locked,
            training_done,
            serdes_ready,
            serdes_enable,
            vsize,
            hsize,
            fvalid,
            lvalid,
            black,
            sof,
            eof,
            sol,
            eol,
            pdata[PIXEL_BITS-1:PIXEL_BITS-8],
            psync,
            pdout_8b,
            psync_8b
        })
    );
end
endgenerate

endmodule
