module gsense_rx_lane(
	rst,
	clkin,
	clkdiv,
	training_pattern,
	data_p,
	data_n,
	locked,
	dataout,
	dbg_phase,
	dbg_bitpos
);

parameter IOSTANDARD="LVDS_25";
parameter DIFF_TERM="TRUE";
parameter DATA_BITS=12;
parameter DATA_RATE="DDR";
parameter MIN_PHASE_WINDOW=8;
parameter IBUF_LOW_PWR="TRUE";
parameter FIRST_BIT="LSB";

localparam CASCADE= DATA_RATE=="DDR" && (DATA_BITS==10 || DATA_BITS==14 || DATA_BITS>=16) ? "TRUE" : "FALSE";
localparam DUAL_CYCLE= DATA_RATE=="DDR" ? (
		(DATA_BITS==12 || DATA_BITS>=16) ? "TRUE" : "FALSE"
	) : (
		DATA_BITS>=10 ? "TRUE" : "FALSE"
	);
localparam ISERDES_WIDTH= DUAL_CYCLE=="TRUE" ? DATA_BITS/2 : DATA_BITS;

input	rst;
input	clkin;
input	clkdiv;
input	[DATA_BITS-1:0] training_pattern;
input	data_p;
input	data_n;
output	locked;
output	[DATA_BITS-1:0] dataout;
output	[4:0] dbg_phase;
output	[4:0] dbg_bitpos;

reg [DATA_BITS-1:0] dataout;
reg locked;

////////////////////////////////////////////////////////////////////////////////
// Input buffer and delay
wire data_ibuf;
IBUFDS #(.IOSTANDARD(IOSTANDARD),.DIFF_TERM(DIFF_TERM),.IBUF_LOW_PWR(IBUF_LOW_PWR)) 
ibufds_i(.I(data_p),.IB(data_n),.O(data_ibuf));

reg idly_rst;
reg idly_inc;
wire data_dly;
wire [4:0] cntvalueout;
(* IODELAY_GROUP = "GSENSE_RX" *)
IDELAYE2 #(.IDELAY_TYPE("VARIABLE")/*,.HIGH_PERFORMANCE_MODE("TRUE")*/) 
idelay_i(
	.CNTVALUEIN(5'b0),
	.C(clkdiv),
	.CE(idly_inc),
	.CINVCTRL(1'b0),
	.DATAIN(1'b0),
	.IDATAIN(data_ibuf),
	.INC(1'b1),
	.LD(1'b0),
	.LDPIPEEN(1'b0),
	.REGRST(idly_rst),
	.CNTVALUEOUT(cntvalueout),
	.DATAOUT(data_dly)
);

////////////////////////////////////////////////////////////////////////////////
// Deserialize to N-bit parallel data
reg ides_rst;
reg bitslip;
(* DONT_TOUCH="TRUE" *)
wire [13:0] byte;
wire shiftout1, shiftout2;
wire clkin_inv = ~clkin;
ISERDESE2 # (
	.DATA_RATE      (DATA_RATE),
	.DATA_WIDTH     (DATA_BITS),
	.IOBDELAY       ("IFD"),
	.INTERFACE_TYPE ("NETWORKING"),
	.SERDES_MODE	("MASTER")
) iserdes_0 (
	.O(),
    .Q1             (byte[0]),
    .Q2             (byte[1]),
    .Q3             (byte[2]),
    .Q4             (byte[3]),
    .Q5             (byte[4]),
    .Q6             (byte[5]),
    .Q7             (byte[6]),
    .Q8             (byte[7]),
	.SHIFTOUT1      (shiftout1),
	.SHIFTOUT2      (shiftout2),
	.BITSLIP        (bitslip),
	.CE1            (1'b1),
	.CE2            (1'b1),
	.CLK            (clkin),
	.CLKB           (clkin_inv),
	.CLKDIV         (clkdiv),
	.CLKDIVP        (1'b0),
	.OCLK           (1'b0),
	.OCLKB          (1'b0),
	.DYNCLKDIVSEL   (1'b0),
	.DYNCLKSEL      (1'b0),
	.D              (1'b0),
	.DDLY           (data_dly),
	.OFB            (1'b0),
	.RST            (ides_rst),
	.SHIFTIN1       (1'b0),
	.SHIFTIN2       (1'b0)
);

generate
if(CASCADE=="TRUE") begin
ISERDESE2 # (
	.DATA_RATE      (DATA_RATE),
	.DATA_WIDTH     (DATA_BITS),
	.IOBDELAY       ("IFD"),
	.INTERFACE_TYPE ("NETWORKING"),
	.SERDES_MODE	("SLAVE")
) iserdes_1 (
	.O(),
    .Q1             (),
    .Q2             (),
    .Q3             (byte[8]),
    .Q4             (byte[9]),
    .Q5             (byte[10]),
    .Q6             (byte[11]),
    .Q7             (byte[12]),
    .Q8             (byte[13]),
	.SHIFTOUT1      (),
	.SHIFTOUT2      (),
	.BITSLIP        (bitslip),
	.CE1            (1'b1),
	.CE2            (1'b1),
	.CLK            (clkin),
	.CLKB           (clkin_inv),
	.CLKDIV         (clkdiv),
	.CLKDIVP        (1'b0),
	.OCLK           (1'b0),
	.OCLKB          (1'b0),
	.DYNCLKDIVSEL   (1'b0),
	.DYNCLKSEL      (1'b0),
	.D              (1'b0),
	.DDLY           (1'b0),
	.OFB            (1'b0),
	.RST            (ides_rst),
	.SHIFTIN1       (shiftout1),
	.SHIFTIN2       (shiftout2)
);
end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Deserialize to N-bit parallel data
reg [DATA_BITS-1:0] word_concat;
reg [DATA_BITS-1:0] word;
reg word_valid;
reg byteslip;
generate
	if(DUAL_CYCLE=="TRUE") begin
		// in dual-cycle mode, concat two bytes into one word
		always @(posedge clkdiv)
		begin
			word_concat <= {word_concat[ISERDES_WIDTH-1:0], byte[ISERDES_WIDTH-1:0]};
		end
		always @(posedge clkdiv, posedge rst)
		begin
			if(rst)
				word_valid <= 1'b0;
			else if(byteslip)
				word_valid <= 1'b0;
			else
				word_valid <= !word_valid;
		end
	end
	else begin
		// normal mode, word is same as byte
		always @(*) word_concat = byte;
		always @(*) word_valid = 1'b1;
	end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// swap bit order if required
function [DATA_BITS-1:0] bit_swap;
	input [DATA_BITS-1:0] data;
	integer i;
	begin
		for(i=0;i<DATA_BITS;i=i+1)
			bit_swap[i] = data[DATA_BITS-i-1];
	end
endfunction
generate
	if(FIRST_BIT=="MSB") begin
		always @(*) word = word_concat;
	end
	else begin
		always @(*) word = bit_swap(word_concat);
	end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Phase alignment
(* ASYNC_REG = "TRUE" *)
reg [DATA_BITS-1:0] word_prev;

reg [3:0] bitpos;
reg bytepos;
reg [5:0] phase;
reg [5:0] timer;
reg [0:0] mark;

integer s1, s1_next;

localparam S1_INIT=0;
localparam S1_PHASE=10, S1_PHASE_LATCH=10, S1_PHASE_NEXT=11, S1_PHASE_CHECK=12,
   	S1_PHASE_MARK=13, S1_PHASE_SET=14;
localparam S1_BIT=20, S1_BIT_SLIP=20, S1_BIT_CHECK=21;
localparam S1_BYTE=30, S1_BYTE_SLIP=30;
localparam S1_LOCK=40, S1_LOCK_PRE=40, S1_LOCK_DONE=41;

always @(posedge clkdiv, posedge rst)
begin
	if(rst) 
		s1 <= S1_INIT;
	else
		s1 <= s1_next;
end

always @(*)
begin
	case(s1)
		S1_INIT: begin
			if(timer==63)
				s1_next = S1_PHASE;
			else
				s1_next = S1_INIT;
		end
		// phase alignment procedure
		S1_PHASE_LATCH: begin
			if(word_valid) // got a word
				s1_next = S1_PHASE_NEXT;
			else
				s1_next = S1_PHASE_LATCH;
		end
		S1_PHASE_NEXT: begin
			s1_next = S1_PHASE_CHECK; // increase idelay for next phase
		end
		S1_PHASE_CHECK: begin
			if(word_valid && timer == 16) // idelay stable
				if(word != word_prev) // a transition point found
					s1_next = S1_PHASE_MARK;
				else if(phase==32) // can not found a transition point anyway, skip
					s1_next = S1_BIT;
				else
					s1_next = S1_PHASE_LATCH;
			else
				s1_next = S1_PHASE_CHECK;
		end
		S1_PHASE_MARK: begin
			if(mark == 1) // continue to search next transition point
				s1_next = S1_PHASE_LATCH;
			else // Found two transition point, valid window can be determined
				s1_next = S1_PHASE_SET;
		end
		S1_PHASE_SET: begin
			if(timer == phase) // set to best phase
				s1_next = S1_BIT;
			else
				s1_next = S1_PHASE_SET;
		end
		// word alignment procedure
		S1_BIT_SLIP: begin // shift one bit
			s1_next = S1_BIT_CHECK; 
		end
		S1_BIT_CHECK: begin
			if(word_valid && timer == 16) // idelay stable
				if(word==training_pattern) // hit
					s1_next = S1_LOCK;
				else if(bitpos==ISERDES_WIDTH) // can not align in this byte. only valid in dual-cycle mode.
					s1_next = S1_BYTE;
				else // try next pit position
					s1_next = S1_BIT_SLIP;
			else
				s1_next = S1_BIT_CHECK;
		end
		S1_BYTE_SLIP: begin // for dual-cycle mode only
			if(byteslip)
				if(bytepos==0) // failed, reset
					s1_next = S1_INIT;
				else
					s1_next = S1_BIT_CHECK;
			else
				s1_next = S1_BYTE_SLIP;
		end
		// last procedure
		S1_LOCK_PRE: begin
			if(word_valid && word!=training_pattern) // not stable, restart
				s1_next = S1_INIT;
			else if(timer == 63) // stable
				s1_next = S1_LOCK_DONE;
			else
				s1_next = S1_LOCK_PRE;
		end
		S1_LOCK_DONE: begin // all sing all song
			s1_next = S1_LOCK_DONE;
		end
		default: begin
			s1_next = 'bx;
		end
	endcase
end

always @(posedge clkdiv, posedge rst)
begin
	if(rst) begin
		locked <= 1'b0;
		timer <= 'b0;
		phase <= 'bx;
		bitpos <= 'bx;
		bitslip <= 1'b0;
		bytepos <= 1'bx;
		byteslip <= 1'b0;
		mark <= 1'bx;
		word_prev <= 'bx;

		idly_inc <= 1'b0;
		idly_rst <= 1'b0;
		ides_rst <= 1'b0;
	end
	else case(s1_next)
		S1_INIT: begin
			timer <= timer+1;
			phase <= 0;
			bitpos <= 0;
			bytepos <= 0;
			mark <= 0;
			bitslip <= 0;
			byteslip <= 0;
			locked <= 1'b0;
			word_prev <= 0;
			idly_inc <= 0;
			if(timer == 0 ) begin
				ides_rst <= 1'b1;
				idly_rst <= 1'b1;
			end
			else if(timer == 32) begin
				ides_rst <= 1'b0;
				idly_rst <= 1'b0;
			end
		end
		S1_PHASE_LATCH: begin
		end
		S1_PHASE_NEXT: begin
			word_prev <= word;
			idly_inc <= 1'b1;
			phase <= phase+1;
			timer <= 'b0;
		end
		S1_PHASE_CHECK: begin
			idly_inc <= 1'b0;
			if(word_valid)
				timer <= timer+1;
		end
		S1_PHASE_MARK: begin
			if(mark==1 && phase>=MIN_PHASE_WINDOW) begin
				// This is a good window
				// Set the target phase
				phase <= 32-phase/2;
				mark <= 0;
			end
			else begin
				// this is first point, or a too small window
				// Set as first point
				phase <= 0;
				mark <= 1;
			end
			timer <= 0;
		end
		S1_PHASE_SET: begin
			idly_inc <= 1'b1;
			timer <= timer+1;
		end
		S1_BIT_SLIP: begin
			idly_inc <= 1'b0;
			bitslip <= 1'b1;
			bitpos <= bitpos+1;
			timer <= 0;
		end
		S1_BIT_CHECK: begin
			bitslip <= 1'b0;
			byteslip <= 1'b0;
			if(word_valid)
				timer <= timer+1;
		end
		S1_BYTE_SLIP: begin
			bitpos <= 0;
			if(word_valid) begin
				byteslip <= 1'b1;
				bytepos <= bytepos+1;
			end
			timer <= 0;
		end
		S1_LOCK_PRE: begin
			if(word_valid)
				timer <= timer+1;
		end
		S1_LOCK_DONE: begin
			locked <= 1'b1;
			timer <= 0;
		end
	endcase
end

////////////////////////////////////////////////////////////////////////////////
// N-bit word Output
always @(posedge clkdiv)
begin
	if(word_valid)
		dataout <= word;
end

//assign dbg_phase = phase;
assign dbg_phase = cntvalueout;
assign dbg_bitpos = {bytepos, bitpos};

endmodule

