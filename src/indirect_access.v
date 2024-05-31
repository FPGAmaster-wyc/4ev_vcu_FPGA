module indirect_access(
    input   aclk,
    input   aresetn,

    input   [0:0] wr_sel,
    input   [3:0] wr_be,
    input   [31:0] wr_din,
    input   wr_en,

    input   [0:0] rd_sel,
    input   rd_en,
    output  [31:0] rd_dout,

    output  [31:0] addr_o,
    output  [31:0] data_o,
    input   [31:0] data_i,
    output  we_o,
    output  re_o
);

reg we_r;
reg re_r;
reg [31:0] addr_r;
reg [31:0] data_r;
always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        addr_r <= 'b0;
        data_r <= 'bx;
        we_r <= 1'b0;
        re_r <= 1'b0;
    end
    else if(wr_sel==1'b0 && wr_en) begin
        if(wr_be[0]) addr_r[7:0] <= wr_din[7:0];
        if(wr_be[1]) addr_r[15:8] <= wr_din[15:8];
        if(wr_be[2]) addr_r[23:16] <= wr_din[23:16];
        if(wr_be[3]) addr_r[31:24] <= wr_din[31:24];
        we_r <= 1'b0;
        re_r <= 1'b0;
    end
    else if(wr_sel==1'b1 && wr_en) begin
        if(wr_be[0]) data_r[7:0] <= wr_din[7:0];
        if(wr_be[1]) data_r[15:8] <= wr_din[15:8];
        if(wr_be[2]) data_r[23:16] <= wr_din[23:16];
        if(wr_be[3]) data_r[31:24] <= wr_din[31:24];
        if(wr_be[3]) we_r <= 1'b1;
        re_r <= 1'b0;
    end
    else if(rd_sel==1'b1 && rd_en) begin
        re_r <= 1'b1;
        we_r <= 1'b0;
    end
    else begin
        if(we_r || re_r) begin
            addr_r <= addr_r+1;
        end
        we_r <= 1'b0;
        re_r <= 1'b0;
    end
end

reg [31:0] rd_dout_r;
always @(*)
begin
    if(rd_sel==1'b0) begin
        rd_dout_r = addr_r;
    end
    else begin
        rd_dout_r = data_i;
    end
end

assign rd_dout = rd_dout_r;
assign addr_o = addr_r;
assign data_o = data_r;
assign we_o = we_r;
assign re_o = re_r;

endmodule
