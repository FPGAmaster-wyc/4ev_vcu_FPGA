module image_dma #(
    parameter ADDR_BITS=32,
    parameter DATA_BITS=64,
    parameter WRITE_BURST_LENGTH=32, // in unit of DATA_BITS
    parameter READ_BURST_LENGTH=32, // in uint of DATA_BITS
    parameter OUTPUT_PACKET_SIZE=256, // in uint of DATA_BITS
    parameter WRITE_LIMIT=(4096*4096) // Bytes limit for write size
) (
    input pclk, // image clock
    input [DATA_BITS-1:0] pdata, // image data
    input pvalid, // data valid
    input eof, // end of frame
    input eol, // end of line

    input aclk,
    input aresetn,

    input [ADDR_BITS-1:0] ADDRESS0, // first buffer in ping-pong
    input [ADDR_BITS-1:0] ADDRESS1, // second buffer in ping-pong

    input enable, // enable/disable DMA operations
    input input_trigger, // write an input image to memory
    input output_trigger, // read an image from memory and output

    // AXI memory port
    output [ADDR_BITS-1:0]m_axi_awaddr,
    output [1:0]m_axi_awburst,
    output [3:0]m_axi_awcache,
    output [7:0]m_axi_awlen,
    output [0:0]m_axi_awlock,
    output [2:0]m_axi_awprot,
    output [3:0]m_axi_awqos,
    output [2:0]m_axi_awsize,
    output m_axi_awvalid,
    input m_axi_awready,
    output [DATA_BITS-1:0]m_axi_wdata,
    output [DATA_BITS/8-1:0]m_axi_wstrb,
    output m_axi_wvalid,
    output m_axi_wlast,
    input m_axi_wready,
    input [1:0]m_axi_bresp,
    input m_axi_bvalid,
    output m_axi_bready,

    output [ADDR_BITS-1:0]m_axi_araddr,
    output [1:0]m_axi_arburst,
    output [3:0]m_axi_arcache,
    output [7:0]m_axi_arlen,
    output [0:0]m_axi_arlock,
    output [2:0]m_axi_arprot,
    output [3:0]m_axi_arqos,
    output [2:0]m_axi_arsize,
    output m_axi_arvalid,
    input m_axi_arready,
    input [DATA_BITS-1:0]m_axi_rdata,
    input m_axi_rlast,
    input [1:0]m_axi_rresp,
    input m_axi_rvalid,
    output m_axi_rready,

    output input_done, // input image done

    // output stream
    output [DATA_BITS-1:0] m_axis_tdata,
    output m_axis_tvalid,
    output m_axis_tlast, // EOP
    output [0:0] m_axis_tuser, // SOF
    input m_axis_tready,

    // output meta-data
    output select, // image in which buffer
    output overflow,

    output output_done // output image done
);

function integer clogb2 (input integer size);
    integer sz;
begin
    sz = size - 1;
    for (clogb2=1; sz>1; clogb2=clogb2+1)
        sz = sz >> 1;
end
endfunction
localparam BYTES = DATA_BITS/8;
localparam BSIZE= clogb2(BYTES);

wire pclk_aresetn = aresetn;

////////////////////////////////////////////////////////////////////////////////
// input buffer
reg [DATA_BITS-1:0] in_fifo_din;
reg in_fifo_wr_en;
wire [DATA_BITS-1:0] in_fifo_dout;
wire in_fifo_rd_en;
wire in_fifo_full;
wire in_fifo_empty;
wire in_fifo_prog_empty;

wire [10:0] in_fifo_wr_count;
wire [10:0] in_fifo_rd_count;
fifo_async #(.DSIZE(DATA_BITS), .ASIZE(10), .MODE("FWFT")) in_fifo_i(
    .wr_rst(!enable),
    .wr_clk(pclk),
    .din(in_fifo_din),
    .wr_en(in_fifo_wr_en),
    .full(in_fifo_full),
    .wr_count(in_fifo_wr_count),
    .rd_rst(!enable),
    .rd_clk(aclk),
    .dout(in_fifo_dout),
    .rd_en(in_fifo_rd_en),
    .empty(in_fifo_empty),
    .rd_count(in_fifo_rd_count)
);
assign in_fifo_prog_empty = in_fifo_rd_count<WRITE_BURST_LENGTH;
assign overflow = in_fifo_full;

(* ASYNC_REG = "TRUE" *)
reg [1:0] input_trigger_r;
wire input_trigger_sync = input_trigger_r[1];
always @(posedge pclk)
begin
    input_trigger_r <= {input_trigger_r, input_trigger};
end

// generate a SOF
reg fflag;
always @(posedge pclk, negedge pclk_aresetn)
begin
    if(!pclk_aresetn) begin
        fflag <= 1'b0;
    end
    else if(!fflag && pvalid) begin
        fflag <= 1'b1;
    end
    else if(eof && pvalid) begin
        fflag <= 1'b0;
    end
end
wire sof = pvalid && !fflag;

reg s1_end;
reg s1_end_of_frame;

integer s1, s1_next;
localparam S1_IDLE=0, S1_VBLANK=1, S1_SOF=2, S1_DATA=3, S1_EOL=4,
    S1_HBLANK=5, S1_INVALID=6, S1_END=7;
always @(posedge pclk, negedge pclk_aresetn)
begin
    if(!pclk_aresetn)
        s1 <= S1_IDLE;
    else if(!enable)
        s1 <= S1_IDLE;
    else
        s1 <= s1_next;
end

always @(*)
begin
    case(s1)
        S1_IDLE: begin
            if(input_trigger_sync)
                s1_next = S1_VBLANK;
            else
                s1_next = S1_IDLE;
        end
        S1_VBLANK: begin
            // discard all input until a SOF found
            if(pvalid && sof)
                s1_next = S1_SOF;
            else
                s1_next = S1_VBLANK;
        end
        S1_SOF: begin
            if(pvalid)
                s1_next = S1_DATA;
            else
                s1_next = S1_INVALID;
        end
        S1_DATA: begin
            if(pvalid)
                if(eol)
                    s1_next = S1_EOL;
                else
                    s1_next = S1_DATA;
            else
                s1_next = S1_INVALID;
        end
        S1_EOL: begin
            if(pvalid)
                s1_next = S1_DATA;
            else
                s1_next = S1_HBLANK;
        end
        S1_HBLANK: begin
            if(s1_end)
                s1_next = S1_END;
            else if(pvalid)
                s1_next = S1_DATA;
            else
                s1_next = S1_HBLANK;
        end
        S1_INVALID: begin
            // abnormal situation but handled for robustness
            if(pvalid)
                s1_next = S1_DATA;
            else
                s1_next = S1_INVALID;
        end
        S1_END: begin
            s1_next = S1_IDLE;
        end
        default: begin
            s1_next = 'bx;
        end
    endcase
end

always @(posedge pclk, negedge pclk_aresetn)
begin
    if(!pclk_aresetn) begin
        in_fifo_wr_en <= 1'b0;
        in_fifo_din <= 'bx;
        s1_end_of_frame <= 0;
        s1_end <= 'bx;
    end
    else case(s1_next)
        S1_IDLE: begin
        end
        S1_VBLANK: begin
            s1_end_of_frame <= 1'b0;
        end
        S1_SOF: begin
            in_fifo_din <= pdata;
            in_fifo_wr_en <= 1'b1;
        end
        S1_DATA: begin
            in_fifo_din <= pdata;
            in_fifo_wr_en <= 1'b1;
        end
        S1_EOL: begin
            in_fifo_din <= pdata;
            in_fifo_wr_en <= 1'b1;
            s1_end <= eof;
        end
        S1_HBLANK: begin
            in_fifo_wr_en <= 1'b0;
        end
        S1_INVALID: begin
            in_fifo_wr_en <= 1'b0;
        end
        S1_END: begin
            s1_end_of_frame <= 1'b1;
        end
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// write to memory
reg [ADDR_BITS-1:0] s2_awaddr;
reg s2_awvalid;
reg s2_wvalid;
reg s2_wlast;
reg s2_select;
reg [ADDR_BITS-1:0] s2_last_address_0;
reg [ADDR_BITS-1:0] s2_last_address_1;
reg s2_end_of_frame;
reg [7:0] s2_count;
reg [ADDR_BITS-1:0] s2_wcnt;
reg s2_flush;
reg s2_s1_done;

assign m_axi_awaddr = s2_awaddr;
assign m_axi_awvalid = s2_awvalid;
assign m_axi_wdata = in_fifo_dout;
assign m_axi_wvalid = s2_wvalid;
assign m_axi_wlast = s2_wlast;
assign in_fifo_rd_en = s2_flush || m_axi_wvalid && m_axi_wready;

assign m_axi_awburst = 2'b01; // INCR
assign m_axi_awcache = 4'b0011; // cacheable & bufferable
assign m_axi_awlen = WRITE_BURST_LENGTH-1;
assign m_axi_awlock = 1'b0;
assign m_axi_awprot = 3'b0;
assign m_axi_awqos = 4'b0;
assign m_axi_awsize = BSIZE;
assign m_axi_wstrb = {BYTES{1'b1}};

assign m_axi_bready = 1'b1;

assign input_done = s2_end_of_frame;
assign select = !s2_select;

integer s2, s2_next;
localparam S2_IDLE=0, S2_READY=1, S2_ADDRESS=2, S2_WAIT=3, S2_INCR=4,
    S2_STROBE=5, S2_ACK=6, S2_END=7, S2_FLUSH=8;

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn)
        s2 <= S2_IDLE;
    else
        s2 <= s2_next;
end

(* ASYNC_REG = "TRUE" *)
reg [2:0] s1_end_of_frame_r;
always @(posedge aclk)
begin
    s1_end_of_frame_r <= {s1_end_of_frame_r,s1_end_of_frame};
end

always @(posedge aclk)
begin
    if(!s1_end_of_frame_r[2] && s1_end_of_frame_r[1])
        s2_s1_done <= 1'b1;
    else if(s2_next == S2_READY)
        s2_s1_done <= 1'b0;
end

always @(*)
begin
    case(s2)
        S2_IDLE: begin
            if(enable)
                s2_next = S2_READY;
            else
                s2_next = S2_IDLE;
        end
        S2_READY: begin
            if(enable)
                if(input_trigger_sync)
                    s2_next = S2_ADDRESS;
                else
                    s2_next = S2_READY;
            else
                s2_next = S2_IDLE;
        end
        S2_ADDRESS: begin
            if(enable)
                if(!s2_s1_done) // ensure S1 has start
                    s2_next = S2_WAIT;
                else
                    s2_next = S2_ADDRESS;
            else
                s2_next = S2_IDLE;
        end
        S2_WAIT, S2_INCR: begin
            if(enable)
                if(in_fifo_empty&&s2_s1_done || s2_wcnt>=WRITE_LIMIT)
                    s2_next = S2_END;
                else if(!in_fifo_prog_empty)
                    s2_next = S2_STROBE;
                else
                    s2_next = S2_WAIT;
            else
                s2_next = S2_IDLE;
        end
        S2_STROBE: begin
            s2_next = S2_ACK;
        end
        S2_ACK: begin
            if(m_axi_awvalid || m_axi_wvalid)
                s2_next = S2_ACK;
            else
                s2_next = S2_INCR;
        end
        S2_END, S2_FLUSH: begin // clear FIFO on exceptions
            if(enable)
                if(in_fifo_empty)
                    s2_next = S2_READY;
                else
                    s2_next = S2_FLUSH;
            else
                s2_next = S2_IDLE;
        end
        default: begin
            s2_next = 'bx;
        end
    endcase
end

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        s2_select <= 1'b0;
        s2_awaddr <= 'bx;
        s2_awvalid <= 1'b0;
        s2_wvalid <= 1'b0;
        s2_wlast <= 1'bx;
        s2_last_address_0 <= 'bx;
        s2_last_address_1 <= 'bx;
        s2_end_of_frame <= 1'b0;
        s2_count <= 'bx;
        s2_wcnt <= 'bx;
        s2_flush <= 1'b0;
    end
    else case(s2_next)
        S2_IDLE: begin
            s2_last_address_0 <= ADDRESS0;
            s2_last_address_1 <= ADDRESS1;
            s2_end_of_frame <= 1'b0;
            s2_select <= 0;
            s2_flush <= 1'b0;
        end
        S2_READY: begin
            s2_flush <= 1'b0;
        end
        S2_ADDRESS: begin
            s2_awaddr <= s2_select ? ADDRESS1 : ADDRESS0;
            s2_end_of_frame <= 1'b0;
            s2_wcnt <= 0;
        end
        S2_WAIT: begin
        end
        S2_STROBE: begin
            s2_awvalid <= 1'b1;
            s2_wvalid <= 1'b1;
            s2_wlast <= 1'b0;
            s2_count <= 0;
        end
        S2_ACK: begin
            if(m_axi_awready)
                s2_awvalid <= 1'b0;
            if(m_axi_wready)
                s2_count <= s2_count+1;
            if(m_axi_wready && s2_count==WRITE_BURST_LENGTH-2)
                s2_wlast <= 1'b1;
            if(m_axi_wready && m_axi_wlast)
                s2_wvalid <= 1'b0;
        end
        S2_INCR: begin
            s2_awaddr <= s2_awaddr + WRITE_BURST_LENGTH*BYTES;
            s2_wcnt <= s2_wcnt + WRITE_BURST_LENGTH*BYTES;
        end
        S2_END: begin
            if(s2_select)
                s2_last_address_1 <= s2_awaddr;
            else
                s2_last_address_0 <= s2_awaddr;
            s2_select <= !s2_select;
            s2_end_of_frame <= 1'b1;
            s2_flush <= 1'b1;
        end
        S2_FLUSH: begin
        end
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// read from memory

reg [ADDR_BITS-1:0] s3_last_addr;
reg [ADDR_BITS-1:0] s3_araddr;
reg s3_arvalid;
reg s3_end_of_frame;
wire s3_ready;

assign m_axi_araddr = s3_araddr;
assign m_axi_arvalid = s3_arvalid;

assign m_axi_arburst = 2'b01; // INCR
assign m_axi_arcache = 4'b0011; // cacheable && bufferable
assign m_axi_arlen = READ_BURST_LENGTH-1;
assign m_axi_arlock = 1'b0;
assign m_axi_arprot = 'b0;
assign m_axi_arqos = 'b0;
assign m_axi_arsize = BSIZE;

integer s3, s3_next;
localparam S3_IDLE=0, S3_SELECT=1, S3_WAIT=2, S3_STROBE=3, S3_ACK=4, 
    S3_INCR=5, S3_END=6;

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn)
        s3 <= S3_IDLE;
    else
        s3 <= s3_next;
end

always @(*)
begin
    case(s3)
        S3_IDLE: begin
            if(output_trigger)
                s3_next = S3_SELECT;
            else
                s3_next = S3_IDLE;
        end
        S3_SELECT: begin
            if(s3_araddr == s3_last_addr) // no data yet
                s3_next = S3_IDLE;
            else
                s3_next = S3_WAIT;
        end
        S3_WAIT: begin
            if(s3_ready)
                s3_next = S3_STROBE;
            else
                s3_next = S3_WAIT;
        end
        S3_STROBE: begin
            if(m_axi_arready)
                s3_next = S3_ACK;
            else
                s3_next = S3_STROBE;
        end
        S3_ACK: begin
            if(m_axi_rvalid && m_axi_rready && m_axi_rlast)
                s3_next = S3_INCR;
            else
                s3_next = S3_ACK;
        end
        S3_INCR: begin
            if(s3_araddr == s3_last_addr)
                s3_next = S3_END;
            else
                s3_next = S3_WAIT;
        end
        S3_END: begin
            s3_next = S3_IDLE;
        end
        default: begin
            s3_next = 'bx;
        end
    endcase
end

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        s3_araddr <= 'bx;
        s3_last_addr <= 'bx;
        s3_arvalid <= 1'b0;
        s3_end_of_frame <= 1'b0;
    end
    else case(s3_next)
        S3_IDLE: begin
        end
        S3_SELECT: begin
            s3_araddr <= s2_select ? ADDRESS0 : ADDRESS1;
            s3_last_addr <= s2_select ? s2_last_address_0 : s2_last_address_1;
        end
        S3_WAIT: begin
        end
        S3_STROBE: begin
            s3_arvalid <= 1'b1;
            s3_end_of_frame <= 1'b0;
        end
        S3_ACK: begin
            s3_arvalid <= 1'b0;
        end
        S3_INCR: begin
            s3_araddr <= s3_araddr + READ_BURST_LENGTH*BYTES;
        end
        S3_END: begin
            s3_end_of_frame <= 1'b1;
        end
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// output buffer
wire [DATA_BITS-1:0] out_fifo_din;
wire out_fifo_wr_en;
wire out_fifo_prog_full;
wire out_fifo_full;
wire [DATA_BITS-1:0] out_fifo_dout;
wire out_fifo_rd_en;
wire out_fifo_almost_empty;
wire out_fifo_empty;

wire [10:0] out_fifo_data_count;
fifo_sync #(.DSIZE(DATA_BITS), .ASIZE(10), .MODE("FWFT")) out_fifo_i(
    .rst(!aresetn),
    .clk(aclk),
    .din(out_fifo_din),
    .wr_en(out_fifo_wr_en),
    .full(out_fifo_full),
    .dout(out_fifo_dout),
    .rd_en(out_fifo_rd_en),
    .empty(out_fifo_empty),
    .data_count(out_fifo_data_count)
);
assign out_fifo_prog_full = out_fifo_data_count>(1024-READ_BURST_LENGTH);
assign out_fifo_almost_empty = out_fifo_data_count<2;

reg s4_tvalid;
reg s4_tlast;
reg s4_sof;
reg s4_end_of_frame;
reg [10:0] s4_count;

assign s3_ready = !out_fifo_prog_full;

assign out_fifo_din = m_axi_rdata;
assign out_fifo_wr_en = m_axi_rvalid;
assign m_axi_rready = !out_fifo_full;

assign out_fifo_rd_en = m_axis_tvalid && m_axis_tready;

assign m_axis_tdata = out_fifo_dout;
assign m_axis_tvalid = s4_tvalid;
assign m_axis_tlast = s4_tlast;
assign m_axis_tuser = s4_sof;

assign output_done = s4_end_of_frame;

integer s4, s4_next;
localparam S4_IDLE=0, S4_WAIT=1, S4_STROBE=2, S4_END=3;

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn)
        s4 <= S4_IDLE;
    else
        s4 <= s4_next;
end

always @(*)
begin
    case(s4)
        S4_IDLE: begin
            if(!out_fifo_empty)
                s4_next = S4_WAIT;
            else
                s4_next = S4_IDLE;
        end
        S4_WAIT: begin
            if(!out_fifo_almost_empty || (s3_end_of_frame && !out_fifo_empty))
                s4_next = S4_STROBE;
            else if(s3_end_of_frame)
                s4_next = S4_END;
            else
                s4_next = S4_WAIT;
        end
        S4_STROBE: begin
            if(m_axis_tready && s4_tvalid && s4_tlast)
                s4_next = S4_WAIT;
            else
                s4_next = S4_STROBE;
        end
        S4_END: begin
            s4_next = S4_IDLE;
        end
        default: begin
            s4_next = 'bx;
        end
    endcase
end

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn)
        s4_end_of_frame <= 1'b0;
    else if(s4_next == S4_WAIT)
        s4_end_of_frame <= 1'b0;
    else if(s4_next == S4_END)
        s4_end_of_frame <= 1'b1;
end

always @(posedge aclk)
begin
    if(s4_next == S4_IDLE)
        s4_sof <= 1'b1;
    else if(m_axis_tvalid && m_axis_tready)
        s4_sof <= 1'b0;
end

always @(posedge aclk)
begin
    if(s4_next == S4_IDLE)
        s4_count <= 0;
    else if(m_axis_tvalid && m_axis_tready) begin
        if(m_axis_tlast)
            s4_count <= 0;
        else
            s4_count <= s4_count+1;
    end
end

always @(*)
begin
    if(s4==S4_STROBE) begin
        if(!out_fifo_almost_empty)
            s4_tvalid = 1;
        else if(s3_end_of_frame && out_fifo_almost_empty && !out_fifo_empty)
            s4_tvalid = 1;
        else
            s4_tvalid = 0;

        if(s4_count==OUTPUT_PACKET_SIZE-1)
            s4_tlast = 1;
        else if(s3_end_of_frame && out_fifo_almost_empty && !out_fifo_empty)
            s4_tlast = 1;
        else
            s4_tlast = 0;
    end
    else begin
        s4_tvalid = 0;
        s4_tlast = 0;
    end
end

endmodule
