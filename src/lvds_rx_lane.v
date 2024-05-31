module lvds_rx_lane #(
    parameter DATA_BITS=8,
    parameter DATA_RATE="DDR",
    parameter MIN_PHASE_WINDOW=8,
    parameter FIRST_BIT="MSB",
    parameter USE_IDELAY="TRUE",
    parameter IDLY_REFCLK_FREQ=300.0
)
(
    input   rst,
    input   ready,
    input   clkin,
    input   clkdiv,
    input   [DATA_BITS-1:0] training_pattern,
    input   data_p,
    input   data_n,
    output  reg locked,
    output  reg [DATA_BITS-1:0] dataout,
    output  [8:0] dbg_phase,
    output  [4:0] dbg_bitpos
);
localparam DUAL_CYCLE = "FALSE";
localparam ISERDES_WIDTH = DUAL_CYCLE=="TRUE" ? DATA_BITS/2 : DATA_BITS;
localparam MAX_PHASE = 512;
localparam IDLY_LATENCY = 4;
localparam BITSLIP_LATENCY = 4;
localparam LOCK_WAIT = 64;

////////////////////////////////////////////////////////////////////////////////
// Input buffer and delay
wire data_ibuf;
IBUFDS ibufds_i(.I(data_p),.IB(data_n),.O(data_ibuf));

reg idly_inc;
reg idly_en_vtc;
wire data_dly;
wire [8:0] cntvalueout;
generate
if (USE_IDELAY == "TRUE") begin
    (* IODELAY_GROUP = "LVDS_RX" *)
    IDELAYE3 #(
        .DELAY_FORMAT("TIME"),
        .DELAY_TYPE("VARIABLE"),
        .REFCLK_FREQUENCY(IDLY_REFCLK_FREQ),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) idelay_0 (
        .CASC_RETURN(1'b0),
        .CASC_IN(1'b0),
        .CASC_OUT(),
        .CLK(clkdiv),
        .CE(idly_inc),
        .INC(1'b1),
        .LOAD(1'b0),
        .CNTVALUEIN(8'b0),
        .CNTVALUEOUT(cntvalueout),
        .DATAIN(1'b0),
        .IDATAIN(data_ibuf),
        .DATAOUT(data_dly),
        .RST(rst),
        .EN_VTC(idly_en_vtc)
    );
end
else begin
    assign data_dly = data_ibuf;
    assign cntvalueout = 'b0;
end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Deserialize to N-bit parallel data
wire [7:0] data_des;
ISERDESE3 # (
    .DATA_WIDTH         (ISERDES_WIDTH),
    .IS_CLK_B_INVERTED  (1),
    .SIM_DEVICE("ULTRASCALE_PLUS")
) iserdes_0 (
    .CLK            (clkin),
    .CLK_B          (clkin),
    .CLKDIV         (clkdiv),
    .D              (data_dly),
    .Q              (data_des),
    .RST            (rst),
    .FIFO_RD_CLK    (1'b0),
    .FIFO_RD_EN     (1'b0),
    .FIFO_EMPTY     (),
    .INTERNAL_DIVCLK()
);

////////////////////////////////////////////////////////////////////////////////
// Bit alignment
//
wire [7:0] byte;
reg [3:0] bitpos;
bitslip #(.DATA_BITS(DATA_BITS)) bitslip_0(
    .clk(clkdiv),
    .bitpos(bitpos),
    .din(data_des),
    .dout(byte)
);

////////////////////////////////////////////////////////////////////////////////
// Deserialize to N-bit parallel data
reg [DATA_BITS-1:0] word_concat;
reg [DATA_BITS-1:0] word;
reg word_valid;
reg byteslip;
reg bitslip;
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
        always @(*) word = bit_swap(word_concat);
    end
    else begin
        always @(*) word = word_concat;
    end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Phase alignment
(* ASYNC_REG = "TRUE" *)
reg [DATA_BITS-1:0] word_prev;

reg bytepos;
reg [9:0] phase;
reg [9:0] timer;
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
            if(timer == 64)
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
            if(word_valid && timer == IDLY_LATENCY) // idelay stable
                if(word != word_prev) // a transition point found
                    s1_next = S1_PHASE_MARK;
                else if(&phase) // can not found a transition point anyway, skip
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
            if(word_valid && timer == BITSLIP_LATENCY) // idelay stable
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
            else if(timer == LOCK_WAIT) // stable
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
        idly_en_vtc <= 1'b1;
    end
    else case(s1_next)
        S1_INIT: begin
            phase <= 0;
            bitpos <= 0;
            bytepos <= 0;
            mark <= 0;
            bitslip <= 0;
            byteslip <= 0;
            locked <= 1'b0;
            word_prev <= 0;
            idly_inc <= 0;
            if(ready)
                timer <= timer+1;
        end
        S1_PHASE_LATCH: begin
            idly_en_vtc <= 1'b0;
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
                phase <= MAX_PHASE-phase/2;
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
            idly_en_vtc <= 1'b1;
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

assign dbg_phase = cntvalueout;
assign dbg_bitpos = {bytepos, bitpos};

endmodule

