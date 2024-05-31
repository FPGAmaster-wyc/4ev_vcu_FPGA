////////////////////////////////////////////////////////////////////////////////
// Frame format decoder for PYTHON sensors PY1300, PY5000, PY25K...
//
// See sensor datasheet for details.
//
// Synchronization
//
// Extract frame & line sync signals from embedded sync. codes.
//
// Pixel Remapping
//
// Pixel data organized as "kernels".
// Each "kernel" consists of N pixels where N is 2*CH.
// These N pixels show on data bus in two consecutive clock cycles.
// Even kernel have normal pixel order.
// Odd kernels have reversed pixel order.
// Thus there are four different pixel layouts as shown bellow.
//
// Input pixel order on DIN (MSB at left):
// Time\CH |CH*|  ...  |CH2|CH1|CH0|    Kernel
//  0    : |N-2|  ...  | 4 | 2 | 0 |    Even
//  1    : |N-1|  ...  | 5 | 3 | 1 |    Even
//  2    : | 1 | 3 | 5 |  ...  |N-1|    Odd
//  3    : | 0 | 2 | 4 |  ...  |N-2|    Odd
//
// This module tranlates input to a simple pixel layout as shown bellow.
//
// Output pixel order on PDATA (MSB at left):
// Time\CH |CH* | ... |CH2 |CH1 |CH0 |
//  0    : |Pc-1| ... | P2 | P1 | P0 |
//  1    : |Pn-1| ... |Pc+2|Pc+1| Pc |
//
// Bit order in a pixel is in MSB first
module python_decode #(
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
    parameter CH=4, // channels
    parameter WIDTH_BITS=12, // horizontal counter bits
    parameter HEIGHT_BITS=12 // vertical counter bits
)(
    input   rst,
    input   clk,
    //FIXME: colored subsampled not implemented yet
    input   mode,   // 0 - normal; 1 - mono subsampled.
    input   [CH*PIXEL_BITS-1:0] din,    // see "Input pixel order"
    input   [PIXEL_BITS-1:0]    sync,   // synchronization
    output  [CH*PIXEL_BITS-1:0] pdata,  // see "Output pixel order"
    output  fvalid,
    output  lvalid,
    output  black,
    output  sof,
    output  eof,
    output  sol,
    output  eol,
    output  [WIDTH_BITS-1:0] hsize,
    output  [HEIGHT_BITS-1:0] vsize
);

reg [CH*PIXEL_BITS-1:0] din_1, din_2;
reg lend_0, lend_1;
reg fend_0, fend_1;
reg fval_1, fval_2;
reg lval_1, lval_2;
reg bval_2;
reg sof_2;
reg eof_2;
reg sol_2;
reg eol_2;
reg [CH*PIXEL_BITS-1:0] dout;
reg [HEIGHT_BITS-1:0] vcnt;
reg [WIDTH_BITS-1:0] hcnt;
reg [HEIGHT_BITS-1:0] vsize_r;
reg [WIDTH_BITS-1:0] hsize_r;
wire [CH*PIXEL_BITS-1:0] map_even_0;
wire [CH*PIXEL_BITS-1:0] map_even_1;
wire [CH*PIXEL_BITS-1:0] map_odd_0;
wire [CH*PIXEL_BITS-1:0] map_odd_1;
wire [CH*PIXEL_BITS-1:0] map_sub_0;
wire [CH*PIXEL_BITS-1:0] map_sub_1;

integer s1, s1_next;
localparam S1_EVEN_0=0, S1_EVEN_1=1, S1_ODD_0=2, S1_ODD_1=3, S1_SUB_0=4, S1_SUB_1=5;

assign pdata = dout;
assign fvalid = fval_2;
assign lvalid = lval_2;
assign black = bval_2;
assign sof = sof_2;
assign eof = eof_2;
assign sol = sol_2;
assign eol = eol_2;
assign hsize = hsize_r;
assign vsize = vsize_r;

always @(posedge clk)
begin
    din_1 <= din;
    din_2 <= din_1;
end

always @(posedge clk, posedge rst)
begin
    if(rst) begin
        lend_0 <= 1'b0;
        lend_1 <= 1'b0;
        fend_0 <= 1'b0;
        fend_1 <= 1'b0;
    end
    else begin
        // END flags has one clock cycle latency
        lend_0 <= sync==LE;
        lend_1 <= lend_0;
        fend_0 <= sync==FE;
        fend_1 <= fend_0;
    end
end

always @(posedge clk, posedge rst)
begin
    if(rst)
        fval_1 <= 1'b0;
    else if(sync==FS)
        fval_1 <= 1'b1; 
    else if(fend_1)
        fval_1 <= 1'b0;
end

always @(posedge clk, posedge rst)
begin
    if(rst)
        lval_1 <= 1'b0;
    else if(sync==LS || sync==FS || sync==BS)
        lval_1 <= 1'b1; 
    else if(lend_1 || fend_1)
        lval_1 <= 1'b0;
end

always @(posedge clk, posedge rst)
begin
    if(rst) begin
        fval_2 <= 1'b0;
        lval_2 <= 1'b0;
        bval_2 <= 1'b0;
    end
    else begin
        fval_2 <= fval_1;
        lval_2 <= lval_1 && fval_1;
        bval_2 <= lval_1 && !fval_1;
    end
end

always @(posedge clk, posedge rst)
begin
    if(rst) begin
        sof_2 <= 1'b0;
        eof_2 <= 1'b0;
        sol_2 <= 1'b0;
        eol_2 <= 1'b0;
    end
    else begin
        sof_2 <= !fval_2 && fval_1;
        eof_2 <= fval_1 && fend_1;
        sol_2 <= !lval_2 && lval_1 && fval_1;
        eol_2 <= lval_1 && (lend_1 || fend_1) && fval_1;
    end
end

always @(posedge clk)
begin
    if(!lval_1)
        hcnt <= 0;
    else
        hcnt <= hcnt+CH;

    if(!fval_1)
        vcnt <= 0;
    else if(lend_1) 
        vcnt <= vcnt+1;

    if(fend_1)
        hsize_r <= hcnt+CH;

    if(fend_1) 
        vsize_r <= vcnt+1;
end

// mode may be asynchronous. sync it.
(* ASYNC_REG = "TRUE" *)
reg [1:0] mode_sync;
always @(posedge clk)
begin
    mode_sync <= {mode_sync, mode};
end

always @(posedge clk, posedge rst)
begin
    if(rst)
        s1 <= S1_EVEN_0;
    else
        s1 <= s1_next;
end

wire start_of_line=lval_1 && !lval_2 && !bval_2;
always @(*)
begin
    if(!mode_sync[1]) begin
        if(start_of_line)
            s1_next = S1_EVEN_0;
        else case(s1)
            S1_EVEN_0: begin // even kernel first cycle
                s1_next = S1_EVEN_1;
            end
            S1_EVEN_1: begin // even kernel second cycle
                s1_next = S1_ODD_0;
            end
            S1_ODD_0: begin // odd kernel first cycle
                s1_next = S1_ODD_1;
            end
            S1_ODD_1: begin // odd kernel second cycle
                s1_next = S1_EVEN_0;
            end
            default: begin
                s1_next = S1_EVEN_0;
            end
        endcase
    end
    else begin
        if(start_of_line)
            s1_next = S1_SUB_0;
        else case(s1)
            S1_SUB_0: begin
                s1_next = S1_SUB_1;
            end
            S1_SUB_1: begin
                s1_next = S1_SUB_0;
            end
            default: begin
                s1_next = S1_SUB_0;
            end
        endcase
    end
end

genvar i;
generate
    for(i=0;i<CH/2;i=i+1) begin
        assign map_even_0[PIXEL_BITS*(2*i+1)-1:PIXEL_BITS*(2*i)] =
            din_1[PIXEL_BITS*(i+1)-1:PIXEL_BITS*i];
        assign map_even_0[PIXEL_BITS*(2*i+2)-1:PIXEL_BITS*(2*i+1)] =
            din[PIXEL_BITS*(i+1)-1:PIXEL_BITS*i];

        assign map_even_1[PIXEL_BITS*(2*i+1)-1:PIXEL_BITS*(2*i)] =
            din_2[PIXEL_BITS*(CH/2+i+1)-1:PIXEL_BITS*(CH/2+i)];
        assign map_even_1[PIXEL_BITS*(2*i+2)-1:PIXEL_BITS*(2*i+1)] =
            din_1[PIXEL_BITS*(CH/2+i+1)-1:PIXEL_BITS*(CH/2+i)];

        assign map_odd_0[PIXEL_BITS*(2*i+1)-1:PIXEL_BITS*(2*i)] =
            din[PIXEL_BITS*(CH-i)-1:PIXEL_BITS*(CH-1-i)];
        assign map_odd_0[PIXEL_BITS*(2*i+2)-1:PIXEL_BITS*(2*i+1)] =
            din_1[PIXEL_BITS*(CH-i)-1:PIXEL_BITS*(CH-1-i)];

        assign map_odd_1[PIXEL_BITS*(2*i+1)-1:PIXEL_BITS*(2*i)] =
            din_1[PIXEL_BITS*(CH/2-i)-1:PIXEL_BITS*(CH/2-1-i)];
        assign map_odd_1[PIXEL_BITS*(2*i+2)-1:PIXEL_BITS*(2*i+1)] =
            din_2[PIXEL_BITS*(CH/2-i)-1:PIXEL_BITS*(CH/2-1-i)];
    end
    for(i=0;i<CH;i=i+1) begin
        assign map_sub_0[PIXEL_BITS*(i+1)-1:PIXEL_BITS*i] =
            din_1[PIXEL_BITS*(i+1)-1:PIXEL_BITS*i];
        assign map_sub_1[PIXEL_BITS*(i+1)-1:PIXEL_BITS*i] =
            din_1[PIXEL_BITS*(CH-i)-1:PIXEL_BITS*(CH-1-i)];
    end
endgenerate

always @(posedge clk)
begin
    case(s1_next)
        S1_EVEN_0: begin
            dout <= map_even_0; // {Pc-1,...,P2,P1,P0}
        end
        S1_EVEN_1: begin
            dout <= map_even_1; // {P2c-1,...,Pc+1,Pc}
        end
        S1_ODD_0: begin
            dout <= map_odd_0; // {Pc-1,...,P2,P1,P0}
        end
        S1_ODD_1: begin
            dout <= map_odd_1; // {P2c-1,...,Pc+1,Pc}
        end
        S1_SUB_0: begin
            dout <= map_sub_0; // {Pc-1,...,P2,P1,P0}
        end
        S1_SUB_1: begin
            dout <= map_sub_1; // {P2c-1,...,Pc+1,Pc}
        end
    endcase
end

endmodule
