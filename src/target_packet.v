////////////////////////////////////////////////////////////////////////////////
// NOTE: pakaging scheme has changed. 
// This module does not care about network payload size any more.
// It only transmit a package when MAX_PER_PACKET has reached or EOF.
// Set MAX_PER_PACKET to a proper value to prevent overflow and leave
// post-processing more timing margin.
module target_packet #(
	parameter HEADER_LENGTH=4,
	parameter FIFO_DEPTH=256,
	parameter MAX_PER_PACKET=90,
	parameter INFO_BITS=128,
	parameter DATA_BITS=32
)(
	input aclk,
	input aresetn,

	input [DATA_BITS-1:0] timestamp,
	input [15:0] hsize,
	input [15:0] vsize,

	input [INFO_BITS-1:0] target_info,
	input target_valid,
	input target_eof,

	output [DATA_BITS-1:0] packet_tdata,
	output packet_tvalid,
	output packet_tlast,
	input packet_tready
);

function integer clogb2 (input integer size);
    integer sz;
begin
	sz = size - 1;
	for (clogb2=1; sz>1; clogb2=clogb2+1)
		sz = sz >> 1;
end
endfunction
localparam CELL_LENGTH=INFO_BITS/DATA_BITS;
localparam ADDR_BITS=clogb2(FIFO_DEPTH);

////////////////////////////////////////////////////////////////////////////////
// simple FIFO for data buffering
reg [INFO_BITS-1:0] mem[0:FIFO_DEPTH-1];
reg [ADDR_BITS:0] waddr;
reg [ADDR_BITS:0] raddr;
reg [INFO_BITS-1:0] rd_dout;
reg [ADDR_BITS:0] data_count;
reg full;
reg empty;
wire rd_en;
wire [INFO_BITS-1:0] wr_din;
wire wr_en;
wire [ADDR_BITS:0] waddr_next = (wr_en && !full) ? waddr+1 : waddr;
wire [ADDR_BITS:0] raddr_next = (rd_en && !empty) ? raddr+1 : raddr;
wire full_next = (waddr_next-raddr_next)==FIFO_DEPTH;
wire empty_next = raddr_next==waddr_next;
always @(posedge aclk, negedge aresetn)
begin
	if(!aresetn) begin
		waddr <= 0;
		raddr <= 0;
		full <= 1'b1;
		empty <= 1'b1;
		data_count <= 0;
		rd_dout <= 0;
	end
	else begin
		waddr <= waddr_next;
		full <= full_next;
		raddr <= raddr_next;
		empty <= empty_next;
		data_count <= waddr_next-raddr_next;
		rd_dout <= mem[raddr_next[ADDR_BITS-1:0]];
	end
end
always @(posedge aclk)
begin
	if(wr_en && !full)
		mem[waddr[ADDR_BITS-1:0]] <= wr_din;
end

////////////////////////////////////////////////////////////////////////////////
assign wr_din = target_info;
assign wr_en = target_valid;

////////////////////////////////////////////////////////////////////////////////
// state machine
integer s1, s1_next;
localparam S1_IDLE=0, S1_SETUP=1, S1_HEADER_0=2, S1_HEADER_1=3,
	S1_DATA_FETCH=4, S1_DATA_SHIFT=5;
localparam WCNT_BITS = (INFO_BITS/DATA_BITS> HEADER_LENGTH) ? clogb2(INFO_BITS/DATA_BITS) : clogb2(HEADER_LENGTH);
reg [WCNT_BITS-1:0] word_cnt;
reg [ADDR_BITS:0] cell_cnt;
reg [DATA_BITS-1:0] tdata_r;
reg tvalid_r;
reg tlast_r;
reg rd_en_r;
reg [ADDR_BITS:0] chunk_length;
reg [INFO_BITS-DATA_BITS-1:0] data_shift;
reg has_more;
reg flush;

assign rd_en = rd_en_r;
assign packet_tdata = tdata_r;
assign packet_tvalid = tvalid_r;
assign packet_tlast = tlast_r;

always @(posedge aclk, negedge aresetn)
begin
	if(!aresetn)
		s1 <= S1_IDLE;
	else
		s1 <= s1_next;
end

always @(posedge aclk, negedge aresetn)
begin
	if(!aresetn)
		flush <= 1'b0;
	else if(target_eof)
		flush <= 1'b1;
	else if(empty)
		flush <= 1'b0;
end

always @(*)
begin
	case(s1)
		S1_IDLE: begin
			if(flush)
				s1_next = S1_SETUP;
			else if(data_count > MAX_PER_PACKET)
				s1_next = S1_SETUP;
			else
				s1_next = S1_IDLE;
		end
		S1_SETUP: begin
			s1_next = S1_HEADER_0;
		end
		S1_HEADER_0: begin
			s1_next = S1_HEADER_1;
		end
		S1_HEADER_1: begin
			if(packet_tready && word_cnt == HEADER_LENGTH-1)
                if(tlast_r)
                    s1_next = S1_IDLE;
                else
                    s1_next = S1_DATA_FETCH;
			else
				s1_next = S1_HEADER_1;
		end
		S1_DATA_FETCH: begin
			s1_next = S1_DATA_SHIFT;
		end
		S1_DATA_SHIFT: begin
			if(packet_tready && word_cnt == CELL_LENGTH-1) 
				if(tlast_r)
					s1_next = S1_IDLE;
				else
					s1_next = S1_DATA_FETCH;
			else
				s1_next = S1_DATA_SHIFT;
		end
		default: begin
			s1_next = 'bx;
		end
	endcase
end

always @(posedge aclk, negedge aresetn)
begin
	if(!aresetn) begin
		tdata_r <= 'bx;
		tvalid_r <= 1'b0;
		tlast_r <= 1'b0;
		rd_en_r <= 1'b0;
		chunk_length <= 'bx;
		word_cnt <= 'bx;
		cell_cnt <= 'bx;
		data_shift <= 'bx;
		has_more <= 1'bx;
	end
	else case(s1_next)
		S1_IDLE: begin
			tvalid_r <= 1'b0;
			tlast_r <= 1'b0;
		end
		S1_SETUP: begin
			if(data_count > MAX_PER_PACKET) begin
				chunk_length <= MAX_PER_PACKET;
				has_more <= 1'b1;
			end
			else begin
				chunk_length <= data_count;
				has_more <= 1'b0;
			end
			cell_cnt <= 0;
		end
		S1_HEADER_0: begin
			word_cnt <= 0;
			tvalid_r <= 1'b1;
			tdata_r <= 32'h1aa11ff1;
		end
		S1_HEADER_1: begin
			if(packet_tready) begin
				case(word_cnt)
					0: tdata_r <= timestamp;
					1: begin 
						tdata_r[15:0] <= chunk_length;
						tdata_r[16] <= has_more;  // 0: last, 1: has more
						tdata_r[31:17] <= 'b0;
					end
					2: begin
						tdata_r[31:16] <= hsize;
						tdata_r[15:0] <= vsize;
					end
				endcase
                // may be last if chunk_lengh is 0
				if(word_cnt+1==HEADER_LENGTH-1)
                    tlast_r <= cell_cnt == chunk_length;
				word_cnt <= word_cnt+1;
			end
		end
		S1_DATA_FETCH: begin
			tdata_r <= rd_dout[DATA_BITS-1:0];
			data_shift <= rd_dout[INFO_BITS-1:DATA_BITS];
			rd_en_r <= 1'b1;
			word_cnt <= 0;
			cell_cnt <= cell_cnt+1;
		end
		S1_DATA_SHIFT: begin
			rd_en_r <= 1'b0;
			if(packet_tready) begin
				tdata_r <= data_shift[DATA_BITS-1:0];
				if(word_cnt+1==CELL_LENGTH-1)
                    tlast_r <= cell_cnt == chunk_length;
				data_shift <= {{DATA_BITS{1'bx}},data_shift[INFO_BITS-DATA_BITS-1:DATA_BITS]};
				word_cnt <= word_cnt+1;
			end
		end
	endcase
end

endmodule
