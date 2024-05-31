module spi_ctl #(
	parameter DATA_BITS=26,
	parameter CLK_DIV=10,
	parameter SCLK_RISE=CLK_DIV/2-1,
	parameter SCLK_FALL=CLK_DIV-1,
	parameter CS_SETUP=1,
	parameter CS_HOLD=1,
	parameter SPARE=3
)(
	input	mclk,
	input	reset,
	input	ac,
	input [DATA_BITS-1:0]	din,
	output reg [DATA_BITS-1:0]	rdata,
	output	vld,
	output	rdy,
	output 	ss_n,
	output reg	sck,
	output reg	mosi,
	input	miso
);
//---------------------------------------------------------------------
integer cs,ns;
reg[7:0] sck_cnt;
reg[7:0] tr_cnt;
reg[DATA_BITS-1:0] data_reg;
//---------------------------------------------------------------------
wire rise_edge,fall_edge;
//---------------------------------------------------------------------
localparam  IDLE 				= 0,
			START				= 1,
			TR					= 2,
			DONE				= 3;
//---------------------------------------------------------------------
always @(posedge mclk or posedge reset)
	if(reset)
		cs <= IDLE;
	else
		cs <= ns;

always @(*)begin
	ns = cs;
	case(cs)
		IDLE: if(ac)
			ns = START;
		START: if(tr_cnt == CS_SETUP)
			ns = TR;
		TR: if(tr_cnt == CS_SETUP + DATA_BITS + CS_HOLD)
			ns = DONE;
		DONE: if(tr_cnt == CS_SETUP+DATA_BITS+CS_HOLD+SPARE)
			ns = IDLE;
	endcase
end
//---------------------------------------------------------------------
assign rise_edge = (sck_cnt == CLK_DIV/2-1);
assign fall_edge = (sck_cnt == CLK_DIV-1);

always @(posedge mclk or posedge reset)
	if(reset)
		sck_cnt <= 'b0;
	else if(fall_edge)
		sck_cnt <= 'b0;
	else if(cs != IDLE)
		sck_cnt <= sck_cnt + 1'b1;
	else
		sck_cnt <= 'b0;

always @(posedge mclk or posedge reset)
	if(reset)
		tr_cnt <= 'b0;
	else if(cs == IDLE)
		tr_cnt <= 'b0;
	else if(fall_edge)
		tr_cnt <= tr_cnt + 1'b1;
//---------------------------------------------------------------------
always @(posedge mclk or posedge reset)
	if(reset)
		sck <= 1'b0;
	else if(sck_cnt == SCLK_RISE && cs == TR && tr_cnt < DATA_BITS+CS_SETUP)
		sck <= 1'b1;
	else if(sck_cnt == SCLK_FALL || cs == IDLE)
		sck <= 1'b0;

always @(posedge mclk)
	if(cs == START)
		data_reg <= din;
	else if(fall_edge && cs == TR)begin
		data_reg <= {data_reg,1'bx};
	end

always @(posedge mclk) // delayed to meet hold timing
	mosi <= data_reg[DATA_BITS-1];

always @(posedge mclk)
	if(fall_edge && cs == TR && tr_cnt < DATA_BITS+CS_SETUP)begin
		rdata <= {rdata, miso};
	end
//---------------------------------------------------------------------
assign rdy = (cs == IDLE);
assign vld = (cs == DONE);
assign ss_n = (cs == IDLE)|(cs == DONE);
//---------------------------------------------------------------------
//---------------------------------------------------------------------

endmodule
