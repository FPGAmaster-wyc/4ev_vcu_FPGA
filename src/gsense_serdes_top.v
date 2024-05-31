////////////////////////////////////////////////////////////////////////////////
// LVDS receiver module with auto-training for image sensors.
// Compatible with Xilinx 7-series devices.
//
//			Valid Configurations Matrix
// ----------------------------------------------------
// DATA_RATE	DATA_BITS	clkin	clkdiv		clkdiv2
// "DDR"			4		1/2x	clkin/2		clkin/2
// "DDR"			6		1/2x	clkin/3		clkin/3
// "DDR"			8		1/2x	clkin/4		clkin/4
// "DDR"			10		1/2x	clkin/5		clkin/5
// "DDR"			12		1/2x	clkin/3		clkin/6
// "DDR"			14		1/2x	clkin/7		clkin/7
// "DDR"			16		1/2x	clkin/4		clkin/8
// "DDR"			20		1/2x	clkin/5		clkin/10
// "DDR"			28		1/2x	clkin/7		clkin/14
// "SDR"			2		1x		clkin/2		clkin/2
// "SDR"			3		1x		clkin/3		clkin/3
// "SDR"			4		1x		clkin/4		clkin/4
// "SDR"			5		1x		clkin/5		clkin/5
// "SDR"			6		1x		clkin/6		clkin/6
// "SDR"			7		1x		clkin/7		clkin/7
// "SDR"			8		1x		clkin/8		clkin/8
// "SDR"			10		1x		clkin/5		clkin/10
// "SDR"			12		1x		clkin/6		clkin/12
// "SDR"			14		1x		clkin/7		clkin/14
// "SDR"			16		1x		clkin/8		clkin/16
//
// Clocks
// ----------------------------------------------------
// clkin, clkdiv, clkdiv2 - see configuration matrix
// data_p, data_n	- differential data lines
// idlyctrl_clk		- 200MHz reference clock
//
// Inputs
// ----------------------------------------------------
// reset			- clear all state
// training_pattern	- pattern for phase alignment
//
// Outputs
// ----------------------------------------------------
// training_done	- training success, data is valid
// training_vtz		- when VTZ is asserted, sensor should output training pattern
// training_sync	- one pulse on SYNC triggers at least one sync pattern on sensor output
// clkout			- parallel data clock
// dataout			- parallel data

module gsense_serdes_top(
	reset, 					// global asynchronous reset

	training_pattern, 		// for bit alignment in each lane.
	idlyctrl_clk, 			// 200MHz reference clock for IDELAYCTRL. 

	clkin,					// source-synchronized clock, SDR or DDR
	clkdiv,					// iserdes clock
	clkdiv2,				// parallel clock. 

	data_p, 				// DDR Data pairs
	data_n,

	enable,					// enable inputs. rise edge triggers training

	training_done, 			// training completion
	training_vtz, 			// VTZERO pin pulled high during training. see GSENSE2000 datasheet
	training_sync, 			// SYNC pin output high or pulse during traing. see GSENSE2000 datasheet

	clkout, 				// Pixel clock connects clkdiv2.
	dataout,				// parallel data output 

	// debug signals
	dbg_lane_locked,
	dbg_lane_phase,
	dbg_lane_bitpos,
	dbg_lane_wordpos
);

parameter LANES = 32;
parameter DIFF_TERM = "TRUE";
parameter IOSTANDARD = "LVDS_25";
parameter DATA_BITS = 12;
parameter DATA_RATE = "DDR";
parameter MIN_PHASE_WINDOW = 8;
parameter IDLYRST_SYNC="FALSE";
parameter IBUF_LOW_PWR="TRUE";
parameter FIRST_BIT="LSB";

input	reset;
input	[DATA_BITS*LANES-1:0] training_pattern;
input	idlyctrl_clk;
input	clkin;
input	clkdiv;
input	clkdiv2;
input	[LANES-1:0] data_p;
input	[LANES-1:0] data_n;
input	enable;
output	training_done;
output	training_vtz;
output	training_sync;

output	clkout;
output	[DATA_BITS*LANES-1:0] dataout;

output	[LANES-1:0] dbg_lane_locked;
output	[5*LANES-1:0] dbg_lane_phase;
output	[5*LANES-1:0] dbg_lane_bitpos;
output	[LANES-1:0] dbg_lane_wordpos;

////////////////////////////////////////////////////////////////////////////////
// Shared IDELAYCTRL
reg idlyctrl_rst;
wire idlyctrl_rdy;
generate
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
endgenerate

(* IODELAY_GROUP = "GSENSE_RX" *)
IDELAYCTRL idelayctrl_i(
	.REFCLK(idlyctrl_clk),
	.RST(idlyctrl_rst),
	.RDY(idlyctrl_rdy)
);

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
	else if(!idlyctrl_rdy)
		rst_sync <= 'b0;
	else
		rst_sync <= {rst_sync, 1'b1};
end

assign ctrl_rst = !rst_sync[1];

// lane_rst controls data lanes
reg lane_rst;

////////////////////////////////////////////////////////////////////////////////
// Data lane receiver with auto training that resolves bit and word
// mis-alignment
wire [LANES-1:0] lane_locked;
wire [DATA_BITS*LANES-1:0] data_in;
wire [5*LANES-1:0] dbg_phase;
wire [5*LANES-1:0] dbg_bitpos;

genvar i;
generate

for(i=0;i<LANES;i=i+1) 
begin:LANE
	gsense_rx_lane #(
		.IOSTANDARD(IOSTANDARD),
		.FIRST_BIT(FIRST_BIT),
		.DIFF_TERM(DIFF_TERM),
		.DATA_BITS(DATA_BITS),
		.DATA_RATE(DATA_RATE),
		.MIN_PHASE_WINDOW(MIN_PHASE_WINDOW),
		.IBUF_LOW_PWR(IBUF_LOW_PWR)
	) lane_i(
		.rst(lane_rst),
		.clkin(clkin),
		.clkdiv(clkdiv),
		.training_pattern(training_pattern[DATA_BITS*(i+1)-1:DATA_BITS*i]),
		.data_p(data_p[i]),
		.data_n(data_n[i]),
		.locked(lane_locked[i]),
		.dataout(data_in[DATA_BITS*(i+1)-1:DATA_BITS*i]),
		.dbg_phase(dbg_phase[5*i+4:5*i]),
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
reg [DATA_BITS*LANES-1:0] dataout;
reg training_vtz;
reg training_sync;
reg training_done;

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
			lane_rst <= !start_sync[2];
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
