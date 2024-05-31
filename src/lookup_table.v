////////////////////////////////////////////////////////////////////////////////
// Writeable Look-up Table
// Port A for update
// Port B for look up
module lookup_table (
    a_clk,
    a_addr,
    a_din,
    a_we,
    a_dout,
    b_clk,
    b_addr,
    b_dout
);

function integer clogb2 (input integer size);
    integer sz;
begin
    sz = size - 1;
    for (clogb2=1; sz>1; clogb2=clogb2+1)
        sz = sz >> 1;
end
endfunction

parameter PORT_A_DEPTH=1024;
parameter PORT_A_DATA_BITS=32;
parameter PORT_B_DATA_BITS=128;
parameter INIT_VALUE=32'hDEADBEEF;

localparam RATIO = PORT_B_DATA_BITS/PORT_A_DATA_BITS;
localparam ADDR_LSBS = clogb2(RATIO);
localparam PORT_A_ADDR_BITS = clogb2(PORT_A_DEPTH);
localparam PORT_B_ADDR_BITS = PORT_A_ADDR_BITS-ADDR_LSBS;
localparam PORT_B_DEPTH = 2**PORT_B_ADDR_BITS;

input a_clk;
input [PORT_A_ADDR_BITS-1:0] a_addr;
input [PORT_A_DATA_BITS-1:0] a_din;
input a_we;
output [PORT_A_DATA_BITS-1:0] a_dout;

input b_clk;
input [PORT_B_ADDR_BITS-1:0] b_addr;
output [PORT_B_DATA_BITS-1:0] b_dout;

reg [PORT_B_DATA_BITS-1:0] b_dout_r;
reg [PORT_A_DATA_BITS-1:0] a_dout_r[0:RATIO-1];
reg [PORT_A_DATA_BITS-1:0] a_dout_sel_r;
reg [ADDR_LSBS-1:0] a_sel;

genvar i;
generate
    for(i=0;i<RATIO;i=i+1) begin
        (* ram_style="block" *)
        reg [PORT_A_DATA_BITS-1:0] mem[0:PORT_B_DEPTH-1];

        initial
        begin:INIT
            integer k;
            for(k=0;k<PORT_B_DEPTH;k=k+1) begin
                mem[k] = INIT_VALUE;
            end
        end

        always @(posedge a_clk)
        begin
            if(a_we && a_addr[ADDR_LSBS-1:0]==i) begin
                mem[a_addr[PORT_A_ADDR_BITS-1:ADDR_LSBS]] <= a_din;
            end
        end

        always @(posedge a_clk)
        begin
            a_dout_r[i] <= mem[a_addr[PORT_A_ADDR_BITS-1:ADDR_LSBS]];
        end

        always @(posedge b_clk)
        begin
            b_dout_r[PORT_A_DATA_BITS*i+PORT_A_DATA_BITS-1:PORT_A_DATA_BITS*i] <= mem[b_addr];
        end
    end
endgenerate

always @(posedge a_clk)
begin
    a_sel <= a_addr[ADDR_LSBS-1:0];
end

always @(*)
begin
    a_dout_sel_r = a_dout_r[a_sel];
end

assign a_dout = a_dout_sel_r;
assign b_dout = b_dout_r;

endmodule


