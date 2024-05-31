// Output = Input*Sigma+Delta
module linear_transform #(
    parameter DATA_BITS=8,
    parameter SIGMA_BITS=8,
    parameter SIGMA_FRAC_BITS=7,
    parameter DELTA_BITS=8
) (
    input   clk,
    input   [DATA_BITS-1:0] data_i,
    input   [SIGMA_BITS-1:0] sigma_i,
    input   [DELTA_BITS-1:0] delta_i,
    input   valid_i,

    output  [DATA_BITS-1:0] data_o,
    output  valid_o
);

localparam PRODUCT_BITS = DATA_BITS+SIGMA_BITS-SIGMA_FRAC_BITS;
localparam SUM_BITS = DELTA_BITS > PRODUCT_BITS ?
                         DELTA_BITS+1 : PRODUCT_BITS+1;

// New_Level = Input_Level*Column_Gain
// where Column_Gain = Gain/(2**G_FRAC_BITS)
function [PRODUCT_BITS-1:0] gain_correction(input [DATA_BITS-1:0] level, input [SIGMA_BITS-1:0] gain);
    reg [DATA_BITS+SIGMA_BITS-1:0] product;
    begin
        product = level*gain;
        if(&level) // keep saturation
            gain_correction = {PRODUCT_BITS{1'b1}};
        else
            gain_correction = product>>SIGMA_FRAC_BITS;
    end
endfunction

// New_Level = Input_Level+Delta
// where Delta is a signed integer
function signed [SUM_BITS-1:0] offset_correction(input [PRODUCT_BITS-1:0] level, input signed [DELTA_BITS-1:0] delta);
    reg signed [SUM_BITS-1:0] sum;
    begin
        sum = $signed({1'b0,level}) + delta;
        if(&level) // keep saturation
            offset_correction = {1'b0, {(SUM_BITS-1){1'b1}}};
        else
            offset_correction = sum;
    end
endfunction

// New_Level =
//  0 (Input_Level < 0)
//  Input_Level (0 <= Input_Level <= 2**DATA_BITS-1)
//  2**DATA_BITS-1 (Input_Level > 2**DATA_BITS-1)
function [DATA_BITS-1:0] crop_level(input signed [SUM_BITS-1:0] level);
    if(level < 0)
        crop_level = 0;
    else if(level > {DATA_BITS{1'b1}})
        crop_level = {DATA_BITS{1'b1}};
    else
        crop_level = level;
endfunction

reg [PRODUCT_BITS-1:0] data_1;
reg [DELTA_BITS-1:0] delta_1;
reg valid_1;
always @(posedge clk)
begin
    data_1 <= gain_correction(data_i, sigma_i);
    delta_1 <= delta_i;
    valid_1 <= valid_i;
end

reg signed [SUM_BITS-1:0] sum_2;
reg [DATA_BITS-1:0] data_2;
reg valid_2;
always @(posedge clk)
begin
    sum_2 = offset_correction(data_1, delta_1);
    data_2 <= crop_level(sum_2);
    valid_2 <= valid_1;
end

assign data_o = data_2;
assign valid_o = valid_2;

endmodule
