module column_level_correction #(
    parameter DATA_BITS = 32,
    parameter PIXEL_BITS = 8,
    parameter GAIN_BITS = 8,
    parameter GAIN_FRAC_BITS = 7,
    parameter OFFSET_BITS = 8,
    parameter WIDTH_BITS = 10,
    parameter N = DATA_BITS/PIXEL_BITS,
    parameter LUT_DATA_BITS = (GAIN_BITS+OFFSET_BITS)*N,
    parameter LUT_INIT_VALUE = 1<<GAIN_FRAC_BITS
)(
    input   clk,
    input   rst,
    input   [DATA_BITS-1:0] data_i,
    input   valid_i,
    input   eof_i,
    input   eol_i,
    output  [DATA_BITS-1:0] data_o,
    output  valid_o,
    output  eof_o,
    output  eol_o,

    output  [WIDTH_BITS-1:0] lut_raddr,
    input   [LUT_DATA_BITS-1:0] lut_rdata
);

///////////////////////////////////////////////////////////////////////////////
// Pipeline
reg valid_1, valid_2, valid_3;
reg eof_1, eof_2, eof_3;
reg eol_1, eol_2, eol_3;
reg [DATA_BITS-1:0] data_1;
wire [DATA_BITS-1:0] data_3;
always @(posedge clk)
begin
    data_1 <= data_i;
    {valid_3, valid_2, valid_1} <= {valid_2, valid_1, valid_i};
    {eof_3, eof_2, eof_1} <= {eof_2, eof_1, eof_i};
    {eol_3, eol_2, eol_1} <= {eol_2, eol_1, eol_i};
end

// generate look-up index
reg [WIDTH_BITS-1:0] lut_raddr_next_1;
always @(posedge clk, posedge rst)
begin
    if(rst) begin
        lut_raddr_next_1 <= 0;
    end
    else if(valid_i) begin
        if(eol_i)
            lut_raddr_next_1 <= 0;
        else
            lut_raddr_next_1 <= lut_raddr_next_1 + 1;
    end
end
assign lut_raddr = lut_raddr_next_1;

// transformation
genvar i;
generate
    for(i=0;i<N;i=i+1) begin:COMP
        wire [PIXEL_BITS-1:0] level_input = data_1[PIXEL_BITS*i+PIXEL_BITS-1:PIXEL_BITS*i];
        wire [GAIN_BITS-1:0] gain = lut_rdata[(OFFSET_BITS+GAIN_BITS)*i+GAIN_BITS-1:(OFFSET_BITS+GAIN_BITS)*i];
        wire [OFFSET_BITS-1:0] offset = lut_rdata[(OFFSET_BITS+GAIN_BITS)*i+GAIN_BITS+OFFSET_BITS-1:(OFFSET_BITS+GAIN_BITS)*i+GAIN_BITS];
        linear_transform #(
            .DATA_BITS(PIXEL_BITS),
            .SIGMA_BITS(GAIN_BITS),
            .SIGMA_FRAC_BITS(GAIN_FRAC_BITS),
            .DELTA_BITS(OFFSET_BITS)
        ) linear_transform_i (
            .clk(clk),
            .data_i(level_input),
            .sigma_i(gain),
            .delta_i(offset),
            .valid_i(valid_1),
            .data_o(data_3[PIXEL_BITS*i+PIXEL_BITS-1:PIXEL_BITS*i]),
            .valid_o()
        );
    end
endgenerate

// output
assign data_o = data_3;
assign valid_o = valid_3;
assign eof_o = eof_3;
assign eol_o = eol_3;

endmodule
