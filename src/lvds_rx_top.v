////////////////////////////////////////////////////////////////////////////////
// LVDS receiver module with auto-training for image sensors.
// Compatible with Xilinx Ultrascale+ devices.
//
//          Valid Configurations Matrix
// ----------------------------------------------------
// DATA_RATE    DATA_BITS   clkin   clkdiv      clkdiv2
// "DDR"            8       1/2x    clkin/4     clkin/4
//
// Clocks
// ----------------------------------------------------
// clkin, clkdiv, clkdiv2 - see configuration matrix
// data_p, data_n   - differential data lines
// idlyctrl_clk     - 300-800MHz reference clock
//
// Inputs
// ----------------------------------------------------
// reset            - clear all state
// training_pattern - pattern for phase alignment
//
// Outputs
// ----------------------------------------------------
// training_done    - training success, data is valid
// training_vtz     - when VTZ is asserted, sensor should output training pattern
// training_sync    - one pulse on SYNC triggers at least one sync pattern on sensor output
// clkout           - parallel data clock
// dataout          - parallel data

module lvds_rx_top #(
    parameter LANES = 8,
    parameter DATA_BITS = 8,
    parameter DATA_RATE = "DDR",
    parameter MIN_PHASE_WINDOW = 8,
    parameter FIRST_BIT = "MSB",
    parameter USE_IDELAY = "TRUE",
    parameter IDLYRST_SYNC = "TRUE",
    parameter IDLY_REFCLK_FREQ = 300.0
)
(
    input   reset,                                      // global asynchronous reset
    input   [DATA_BITS*LANES-1:0] training_pattern,     // for bit alignment in each lane.
    input   idlyctrl_clk,                               // reference clock for IDELAYCTRL. 
    input   clkin,                                      // source-synchronized DDR clock
    input   clkdiv,                                     // iserdes clock
    input   clkdiv2,                                    // parallel clock. 
    input   [LANES-1:0] data_p,                         // DDR Data pairs
    input   [LANES-1:0] data_n,
    input   enable,                                     // enable inputs. rise edge triggers training
    output  reg training_done,                              // training completion
    output  reg training_vtz,                               // VTZERO pin pulled high during training.
    output  reg training_sync,                              // SYNC pin output high or pulse during traing.

    output  clkout,                                     // Pixel clock driven by clkdiv2.
    output  reg [DATA_BITS*LANES-1:0] dataout,              // parallel data output 

    // debug interface
    output  [LANES-1:0] dbg_lane_locked,
    output  [9*LANES-1:0] dbg_lane_phase,
    output  [5*LANES-1:0] dbg_lane_bitpos,
    output  [LANES-1:0] dbg_lane_wordpos
);

////////////////////////////////////////////////////////////////////////////////
wire idlyctrl_rdy;
generate
if(USE_IDELAY == "TRUE") begin
    // Shared IDELAYCTRL
    reg idlyctrl_rst;
    if(IDLYRST_SYNC=="TRUE") begin
        // Ensure 52ns minimum reset pulse width
        reg [3:0] idlyctrl_rst_tmr;
        always @(posedge idlyctrl_clk, posedge reset)
        begin
            if(reset) begin
                idlyctrl_rst_tmr <= 0;
                idlyctrl_rst <= 1'b1;
            end
            else if(!(&idlyctrl_rst_tmr)) begin
                idlyctrl_rst_tmr <= idlyctrl_rst_tmr+1;
                idlyctrl_rst <= 1'b1;
            end
            else begin
                idlyctrl_rst <= 1'b0;
            end
        end
    end
    else begin
        always @(*) idlyctrl_rst = reset;
    end

    (* IODELAY_GROUP = "LVDS_RX" *)
    IDELAYCTRL #(
        .SIM_DEVICE("ULTRASCALE")
    ) idlyctrl_0 (
        .REFCLK(idlyctrl_clk),
        .RST(idlyctrl_rst),
        .RDY(idlyctrl_rdy)
    );
end
else begin
    assign idlyctrl_rdy = 1'b1;
end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Local resets
// ctrl_rst resets control logic and is synchronized to slowest clock to ensure
// phase relationship between clock domains.
(* ASYNC_REG="TRUE" *)
reg [1:0] rst_sync;
wire ctrl_rst;

always @(posedge clkdiv2, posedge reset)
begin
    if(reset)
        rst_sync <= 'b0;
    else
        rst_sync <= {rst_sync, 1'b1};
end

assign ctrl_rst = !rst_sync[1];

// lane_rst controls data lanes
reg lane_rst;
wire lane_ready;

////////////////////////////////////////////////////////////////////////////////
// Data lane receiver with auto training that resolves bit and word
// mis-alignment
wire [LANES-1:0] lane_locked;
wire [DATA_BITS*LANES-1:0] data_in;
wire [9*LANES-1:0] dbg_phase;
wire [5*LANES-1:0] dbg_bitpos;

genvar i;
generate

for(i=0;i<LANES;i=i+1) 
begin:LANE
    lvds_rx_lane #(
        .FIRST_BIT(FIRST_BIT),
        .DATA_BITS(DATA_BITS),
        .DATA_RATE(DATA_RATE),
        .MIN_PHASE_WINDOW(MIN_PHASE_WINDOW),
        .USE_IDELAY(USE_IDELAY),
        .IDLY_REFCLK_FREQ(IDLY_REFCLK_FREQ)
    ) lane_i(
        .rst(lane_rst),
        .ready(lane_ready),
        .clkin(clkin),
        .clkdiv(clkdiv),
        .training_pattern(training_pattern[DATA_BITS*(i+1)-1:DATA_BITS*i]),
        .data_p(data_p[i]),
        .data_n(data_n[i]),
        .locked(lane_locked[i]),
        .dataout(data_in[DATA_BITS*(i+1)-1:DATA_BITS*i]),
        .dbg_phase(dbg_phase[9*i+8:9*i]),
        .dbg_bitpos(dbg_bitpos[5*i+4:5*i])
    );
end
endgenerate

assign dbg_lane_locked = lane_locked;
assign dbg_lane_phase = dbg_phase;
assign dbg_lane_bitpos = dbg_bitpos;

////////////////////////////////////////////////////////////////////////////////
// Auto-training control FSM
integer s1, s1_next;

localparam S1_IDLE = 0, S1_RESET_LANE = 1, S1_LANE_TRAINING = 2,
    S1_BLANK = 3, S1_SYNC = 4, S1_LATENCY = 5, S1_ADJUST = 6,
    S1_DONE = 7;

reg [LANES-1:0] lane_sync;
reg [LANES-1:0] lane_sel;

// Detect training pattern removal for aligning between lanes
genvar j;
generate
    for(j=0;j<LANES;j=j+1)
    begin:LANE_SYNC
        always @(posedge clkdiv2) 
            lane_sync[j] <= data_in[DATA_BITS*(j+1)-1:DATA_BITS*j]!=
                training_pattern[DATA_BITS*(j+1)-1:DATA_BITS*j];
    end
endgenerate

// Detect training_start rise edge
(* ASYNC_REG="TRUE" *)
reg [2:0] start_sync;
reg start_r;

always @(posedge clkdiv2, posedge ctrl_rst)
begin
    if(ctrl_rst)
        start_sync <= 'b0;
    else
        start_sync <= {start_sync, enable};
end

always @(posedge clkdiv2, posedge ctrl_rst)
begin
    if(ctrl_rst)
        start_r <= 1'b0;
    else if(s1_next == S1_RESET_LANE)
        start_r <= 1'b0;
    else if(!start_sync[2] && start_sync[1])
        start_r <= 1'b1;
end

assign lane_ready = idlyctrl_rdy && start_sync[2];

////////////////////////////////////////////////////////////////////////////////
// FSM

always @(posedge clkdiv2, posedge ctrl_rst)
begin
    if(ctrl_rst)
        s1 <= S1_IDLE;
    else
        s1 <= s1_next;
end

always @(*)
begin
    case(s1)
        S1_IDLE: begin
            if(start_r)
                s1_next = S1_RESET_LANE;
            else
                s1_next = S1_IDLE;
        end
        S1_RESET_LANE: begin
            s1_next = S1_LANE_TRAINING;
        end
        S1_LANE_TRAINING: begin
            if(&lane_locked) // All lanes locked
                //s1_next = S1_DONE;
                s1_next = S1_SYNC;
            else
                s1_next = S1_LANE_TRAINING;
        end
        // Now each lane is bit and word corrected. We need to further resolve channel
        // mis-alignment
        S1_SYNC: begin
            s1_next = S1_LATENCY;
        end
        S1_LATENCY: begin
            if(|lane_sync) // found any sync header
                s1_next = S1_ADJUST;
            else // wait for sync header
                s1_next = S1_LATENCY;
        end
        S1_ADJUST: begin
            s1_next = S1_DONE;
        end
        S1_DONE: begin
            // all-sing-all-song
            s1_next = S1_IDLE;
        end
        default: begin
            s1_next = 'bx;
        end
    endcase
end

always @(posedge clkdiv2, posedge ctrl_rst)
begin
    if(ctrl_rst) begin
        lane_rst <= 1'b1;
        training_vtz <= 1'b0;
        training_sync <= 1'b0;
        training_done <= 1'b0;
        lane_sel <= 'b0;
    end
    else case(s1_next)
        S1_IDLE: begin
            lane_rst <= 1'b0;
            training_vtz <= 1'b0;
            training_sync <= 1'b0;
        end
        S1_RESET_LANE: begin
            lane_rst <= 1'b1;

            // Pull VTZERO and SYNC high to force sensor output training
            // pattern
            training_vtz <= 1'b1;
            training_sync <= 1'b1;

            training_done <= 1'b0;
        end
        S1_LANE_TRAINING: begin
            lane_rst <= 1'b0;
        end
        S1_BLANK: begin
            // Clear SYNC to clear training pattern
            training_vtz <= 1'b0;
            training_sync <= 1'b0;
        end
        S1_SYNC: begin
            // Assert SYNC again to request for a data line
            training_vtz <= 1'b0;
            training_sync <= 1'b1;
        end
        S1_LATENCY: begin
            training_sync <= 1'b0;
        end
        S1_ADJUST: begin
            // Now we can assume channel relationships based on lane_sync.
            // If lane_sync[i]==1, then lane i is in first group.
            // Otherwise, it is in the other group that is one word behind.
            // Since maximum phase difference is limited, there should be no
            // other situations.
            lane_sel <= lane_sync;
        end
        S1_DONE: begin
            training_vtz <= 1'b0;
            training_sync <= 1'b0;
            training_done <= 1'b1;
        end
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// Output stage

reg [DATA_BITS*LANES-1:0] data_0;

always @(posedge clkdiv2) data_0 <= data_in;

genvar k;
generate
    for(k=0;k<LANES;k=k+1) 
    begin:LANE_OUT
        always @(posedge clkdiv2)
        begin
            if(lane_sel[k])
                dataout[DATA_BITS*(k+1)-1:DATA_BITS*k] <= data_0[DATA_BITS*(k+1)-1:DATA_BITS*k];
            else
                dataout[DATA_BITS*(k+1)-1:DATA_BITS*k] <= data_in[DATA_BITS*(k+1)-1:DATA_BITS*k];
        end
    end
endgenerate

assign clkout = clkdiv2;
assign dbg_lane_wordpos = lane_sel;
endmodule
