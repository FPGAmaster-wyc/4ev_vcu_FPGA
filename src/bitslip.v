module bitslip (
    clk,
    din,
    bitpos,
    dout
);
function integer clogb2 (input integer size);
    integer sz;
begin
    sz = size - 1;
    for (clogb2=1; sz>1; clogb2=clogb2+1)
        sz = sz >> 1;
end
endfunction
parameter DATA_BITS = 8;
parameter CNT_BITS = clogb2(DATA_BITS);

input   clk;
input   [CNT_BITS-1:0] bitpos;
input   [DATA_BITS-1:0] din;
output  reg [DATA_BITS-1:0] dout;

reg [DATA_BITS-1:0] din_1;
reg [2*DATA_BITS-1:0] dual_shift;

always @(*)
begin
    //dual_shift = ({din_1, din}<<bitpos);
    dual_shift = ({din, din_1}>>bitpos);
end

always @(posedge clk)
begin
    din_1 <= din;
    //dout <= dual_shift[2*DATA_BITS-1:DATA_BITS];
    dout <= dual_shift[DATA_BITS-1:0];
end

endmodule
