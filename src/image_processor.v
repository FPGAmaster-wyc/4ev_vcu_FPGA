module image_processor #(
    parameter DATA_BITS=40,
    parameter WIDTH_BITS=12, // 4K
    parameter PIXEL_BITS=10,
    parameter CLC_GAIN_BITS=16,
    parameter CLC_GAIN_FRAC_BITS=8,
    parameter CLC_OFFSET_BITS=16
) (
    // processor core clock
    input   aclk,
    input   aresetn,

    // raw image input MSB at left
    input   [DATA_BITS-1:0] img_data,
    input   img_valid,
    input   img_eof,
    input   img_eol,
    input   [15:0] img_hsize,
    input   [15:0] img_vsize,

    // CLC LUT input
    input   [WIDTH_BITS-1:0] clc_waddr,
    input   [CLC_GAIN_BITS+CLC_OFFSET_BITS-1:0] clc_wdata,
    input   clc_wen,
    output  [CLC_GAIN_BITS+CLC_OFFSET_BITS-1:0] clc_rdata,

    // 8-bit post-process image output
    output  [DATA_BITS/PIXEL_BITS*8-1:0] post_data,
    output  post_valid,
    output  post_eof,
    output  post_eol,

    input   [31:0] time_abs,

    // tag package output
    output  [31:0] tag_tdata,
    output  tag_tvalid,
    output  tag_tlast,
    input   tag_tready
);

localparam N=DATA_BITS/PIXEL_BITS;

////////////////////////////////////////////////////////////////////////////////
// CLC
wire [DATA_BITS-1:0] clc_data;
wire clc_valid;
wire clc_eof;
wire clc_eol;
wire [WIDTH_BITS-1:0] clc_lut_raddr;
wire [(CLC_GAIN_BITS+CLC_OFFSET_BITS)*N-1:0] clc_lut_rdata;
column_level_correction #(
    .DATA_BITS(DATA_BITS),
    .PIXEL_BITS(PIXEL_BITS),
    .GAIN_BITS(CLC_GAIN_BITS),
    .GAIN_FRAC_BITS(CLC_GAIN_FRAC_BITS),
    .OFFSET_BITS(CLC_OFFSET_BITS),
    .WIDTH_BITS(WIDTH_BITS)
) column_level_correction_0 (
    .clk(aclk),
    .rst(!aresetn),
    .data_i(img_data),
    .valid_i(img_valid),
    .eof_i(img_eof),
    .eol_i(img_eol),
    .data_o(clc_data),
    .valid_o(clc_valid),
    .eof_o(clc_eof),
    .eol_o(clc_eol),
    .lut_raddr(clc_lut_raddr),
    .lut_rdata(clc_lut_rdata)
);

// column level correction table
lookup_table #(
    .PORT_A_DEPTH(2**WIDTH_BITS),
    .PORT_A_DATA_BITS(CLC_GAIN_BITS+CLC_OFFSET_BITS),
    .PORT_B_DATA_BITS((CLC_GAIN_BITS+CLC_OFFSET_BITS)*N),
    .INIT_VALUE(32'h00000100)
) clc_lut_0 (
    .a_clk(aclk),
    .a_addr(clc_waddr[WIDTH_BITS-1:0]),
    .a_din(clc_wdata[CLC_GAIN_BITS+CLC_OFFSET_BITS-1:0]),
    .a_we(clc_wen),
    .a_dout(clc_rdata),
    .b_clk(aclk),
    .b_addr(clc_lut_raddr),
    .b_dout(clc_lut_rdata)
);

////////////////////////////////////////////////////////////////////////////////
// Round to 8-bit
function [7:0] round(input [PIXEL_BITS-1:0] data);
    reg carry;
    reg [8:0] sum;
    begin
        if(PIXEL_BITS>8)
            carry = data[PIXEL_BITS-9];
        sum = data[PIXEL_BITS-1:PIXEL_BITS-8]+carry;
        if(sum[8]) // saturate
            round = 8'hFF;
        else
            round = sum[7:0];
    end
endfunction

wire [N*8-1:0] rnd_data_a;
reg [N*8-1:0] rnd_data;
reg rnd_valid;
reg rnd_eof;
reg rnd_eol;
genvar i;
generate
    for(i=0;i<N;i=i+1) begin
        assign rnd_data_a[8*i+7:8*i] = round(clc_data[10*i+9:10*i]);
    end
endgenerate
always @(posedge aclk)
begin
    rnd_data <= rnd_data_a;
    rnd_valid <= clc_valid;
    rnd_eof <= clc_eof;
    rnd_eol <= clc_eol;
end

assign post_data = rnd_data;
assign post_valid = rnd_valid;
assign post_eof = rnd_eof;
assign post_eol = rnd_eol;
////////////////////////////////////////////////////////////////////////////////
// TODO: use partial dynamic configuration for algorithm cores
// Detection
localparam C_PIXEL_BITS = 8;
localparam X_BITS = 12;
localparam X_FRAC_BITS = 10;
localparam Y_BITS = 12;
localparam Y_FRAC_BITS = 10;
localparam SIZE_BITS = X_BITS+Y_BITS;
localparam WEIGHT_BITS = C_PIXEL_BITS+SIZE_BITS;
localparam XF_BITS = X_BITS+X_FRAC_BITS;
localparam YF_BITS = Y_BITS+Y_FRAC_BITS;

wire [WEIGHT_BITS-1:0] target_weight;
wire [SIZE_BITS-1:0] target_size;
wire [C_PIXEL_BITS-1:0] target_level;
wire [XF_BITS-1:0] target_x;
wire [XF_BITS-1:0] target_y;
wire target_valid;
wire target_eof;
wire [X_BITS-1:0] target_xl;
wire [X_BITS-1:0] target_xr;
wire [Y_BITS-1:0] target_yt;
wire [Y_BITS-1:0] target_yb;
wire [2:0] det_status;
/*
ObjectDetectionTop detect_0
(
    .rst_i(!aresetn),
    .clk_i(aclk),

    .pclk_i(aclk),
    .pdata_i(post_data),
    .pvalid_i(post_valid),
    .peol_i(post_eol),
    .peof_i(post_eof),

    .threshold_i(128),
    .status_o(det_status),
    
    .weight_o(target_weight),
    .size_o(target_size),
    .level_o(target_level),
    .x_int_o(target_x[XF_BITS-1:X_FRAC_BITS]),
    .x_frac_o(target_x[X_FRAC_BITS-1:0]),
    .y_int_o(target_y[YF_BITS-1:Y_FRAC_BITS]),
    .y_frac_o(target_y[Y_FRAC_BITS-1:0]),
    .x_left_o(target_xl),
    .x_right_o(target_xr),
    .y_top_o(target_yt),
    .y_bottom_o(target_yb),
    .valid_o(target_valid),
    .eof_o(target_eof)
);
*/

////////////////////////////////////////////////////////////////////////////////
// Tag output
// mark a precise timestamp at frame input
// generate a SOF
reg fflag;
always @(posedge aclk)
begin
    if(img_eof && img_valid) begin
        fflag <= 1'b0;
    end
    else if(!fflag && img_valid) begin
        fflag <= 1'b1;
    end
end
wire sof = img_valid && !fflag;
(*ASYNC_REG = "TRUE" *)
reg [1:0] time_mark_sync_r;
reg [31:0] timestamp;
always @(posedge aclk)
begin
    time_mark_sync_r <= {time_mark_sync_r, sof};
    if(time_mark_sync_r[1])
        timestamp <= time_abs;
end

wire [127:0] target_info;
assign target_info[31:0] = target_x;
assign target_info[63:32] = target_y;
assign target_info[71:64] = target_level;
assign target_info[95:72] = target_size;
assign target_info[127:96] = 0; // reserved for index

target_packet packet_0(
    .aclk(aclk),
    .aresetn(aresetn),

    .timestamp(timestamp),
    .hsize(img_hsize),
    .vsize(img_vsize),

    .target_info(target_info),
    .target_valid(target_valid),
    .target_eof(target_eof),

    .packet_tdata(tag_tdata),
    .packet_tvalid(tag_tvalid),
    .packet_tlast(tag_tlast),
    .packet_tready(tag_tready)
);

endmodule
