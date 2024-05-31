module image_stream #(
    parameter ADDR_BITS=32,
    parameter DATA_BITS=64,
    parameter WRITE_BURST_LENGTH=16,
    parameter READ_BURST_LENGTH=16,
    parameter OUTPUT_PACKET_SIZE=1024/DATA_BITS/8,
    parameter WRITE_LIMIT=(4096*4096)
) (
    input   aclk,
    input   aresetn,

    output  [ADDR_BITS-1:0] m_axi_awaddr,
    output  [1:0] m_axi_awburst,
    output  [3:0] m_axi_awcache,
    output  [7:0] m_axi_awlen,
    output  [0:0] m_axi_awlock,
    output  [2:0] m_axi_awprot,
    output  [3:0] m_axi_awqos,
    output  [2:0] m_axi_awsize,
    output  m_axi_awvalid,
    input   m_axi_awready,
    output  [DATA_BITS-1:0] m_axi_wdata,
    output  [DATA_BITS/8-1:0] m_axi_wstrb,
    output  m_axi_wvalid,
    output  m_axi_wlast,
    input   m_axi_wready,
    input   [1:0] m_axi_bresp,
    input   m_axi_bvalid,
    output  m_axi_bready,
    output  [ADDR_BITS-1:0] m_axi_araddr,
    output  [1:0] m_axi_arburst,
    output  [3:0] m_axi_arcache,
    output  [7:0] m_axi_arlen,
    output  [0:0] m_axi_arlock,
    output  [2:0] m_axi_arprot,
    output  [3:0] m_axi_arqos,
    output  [2:0] m_axi_arsize,
    output  m_axi_arvalid,
    input   m_axi_arready,
    input   [DATA_BITS-1:0] m_axi_rdata,
    input   m_axi_rlast,
    input   [1:0] m_axi_rresp,
    input   m_axi_rvalid,
    output  m_axi_rready,

    input   [ADDR_BITS-1:0] IMG_DMA_ADDR0,
    input   [ADDR_BITS-1:0] IMG_DMA_ADDR1,
    input   [15:0] IMG_PACKET_DELAY,
    input   [31:0] PIXEL_TYPE,

    input   vcap_enable,
    output  vcap_current,
    output  vcap_in_done,
    output  vcap_out_done,
    input   vcap_trigger,
    output  [15:0] vcap_width,
    output  [15:0] vcap_height,

    input   gvsp_img_enable,

    input   cam_pclk, // image clock
    input   [DATA_BITS-1:0] cam_pdata, // image data
    input   cam_pvalid, // data valid
    input   cam_eof, // end of frame
    input   cam_eol, // end of line
    input   [15:0] cam_hsize,
    input   [15:0] cam_vsize,

    output  [7:0] gvsp_img_tdata,
    output  gvsp_img_tvalid,
    output  gvsp_img_tlast,
    input   gvsp_img_tready,

    output  overflow,

    input   [31:0] time_sec,
    input   [31:0] time_ns,
    input   tick_us
);

////////////////////////////////////////////////////////////////////////////////
// Frame grabber DMA
wire [DATA_BITS-1:0] img_axis_tdata;
wire img_axis_tvalid;
wire img_axis_tlast;
wire img_axis_tuser;
wire img_axis_tready;
wire vcap_read_done;
reg output_trigger;

image_dma #(
    .ADDR_BITS(ADDR_BITS),
    .DATA_BITS(DATA_BITS),
    .WRITE_BURST_LENGTH(WRITE_BURST_LENGTH),
    .READ_BURST_LENGTH(READ_BURST_LENGTH),
    .OUTPUT_PACKET_SIZE(OUTPUT_PACKET_SIZE),
    .WRITE_LIMIT(WRITE_LIMIT)
)image_dma_0(
    .pclk(cam_pclk),
    .pdata(cam_pdata),
    .pvalid(cam_pvalid),
    .eof(cam_eof),
    .eol(cam_eol),

    .aclk(aclk),
    .aresetn(aresetn),

    .ADDRESS0(IMG_DMA_ADDR0),
    .ADDRESS1(IMG_DMA_ADDR1),

    .enable(vcap_enable),
    .input_trigger(1'b1),
    .output_trigger(output_trigger),

    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awcache(m_axi_awcache),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awlock(m_axi_awlock),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_awqos(m_axi_awqos),
    .m_axi_awready(m_axi_awready),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wready(m_axi_wready),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),

    .m_axi_araddr(m_axi_araddr),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arlock(m_axi_arlock),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arqos(m_axi_arqos),
    .m_axi_arready(m_axi_arready),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rready(m_axi_rready),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rvalid(m_axi_rvalid),

    .input_done(vcap_in_done),

    .m_axis_tdata(img_axis_tdata),
    .m_axis_tvalid(img_axis_tvalid),
    .m_axis_tlast(img_axis_tlast),
    .m_axis_tuser(img_axis_tuser),
    .m_axis_tready(img_axis_tready),

    .select(vcap_current),

    .overflow(overflow),

    .output_done(vcap_read_done)
);

reg img_in_done_r;
wire img_in_done = !img_in_done_r && vcap_in_done;
always @(posedge aclk)
begin
    img_in_done_r <= vcap_in_done;
end

// Latch previous image size
reg [15:0] vcap_width_r;
reg [15:0] vcap_height_r;
always @(posedge aclk)
begin
    if(img_in_done) begin
        vcap_width_r <= cam_hsize;
        vcap_height_r <= cam_vsize;
    end
end
assign vcap_width = vcap_width_r;
assign vcap_height = vcap_height_r;

// keep a timestamp for image input
reg [63:0] img_timestamp;
always @(posedge aclk)
begin
    if(img_in_done)
        img_timestamp <= {time_sec, time_ns};
end

////////////////////////////////////////////////////////////////////////////////
// GVSP packet generation
gvsp_image #(.DATA_BITS(DATA_BITS)) gvsp_image_0(
    .aclk(aclk),
    .aresetn(aresetn),

    .enable(1'b1),

    .PACKET_DELAY(IMG_PACKET_DELAY),
    .tick_us(tick_us),

    .hsize(vcap_width),
    .vsize(vcap_height),
    .timestamp(img_timestamp),
    .pixel_type(PIXEL_TYPE),
    .end_of_frame(vcap_read_done),

    .s_axis_tdata(img_axis_tdata),
    .s_axis_tvalid(img_axis_tvalid),
    .s_axis_tlast(img_axis_tlast),
    .s_axis_tuser(img_axis_tuser),
    .s_axis_tready(img_axis_tready),

    .m_axis_tdata(gvsp_img_tdata),
    .m_axis_tvalid(gvsp_img_tvalid),
    .m_axis_tlast(gvsp_img_tlast),
    .m_axis_tready(gvsp_img_tready),

    .block_done(vcap_out_done)
);

////////////////////////////////////////////////////////////////////////////////
// GVSP output control
reg gvsp_trigger;
integer s1, s1_next;
localparam S1_IDLE=0, S1_STROBE=1, S1_WAIT=2;

// latch a data valid flag
always @(posedge aclk)
begin
    if(!gvsp_img_enable)
        gvsp_trigger <= 1'b0;
    else if(img_in_done)
        gvsp_trigger <= 1'b1;
    else if(gvsp_trigger && s1 == S1_IDLE)
        gvsp_trigger <= 1'b0;
end

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn)
        s1 <= S1_IDLE;
    else
        s1 <= s1_next;
end

always @(*)
begin
    case(s1)
        S1_IDLE: begin
            if(gvsp_trigger)
                s1_next = S1_STROBE;
            else
                s1_next = S1_IDLE;
        end
        S1_STROBE: begin
            if(m_axi_arvalid)
                s1_next = S1_WAIT;
            else
                s1_next = S1_STROBE;
        end
        S1_WAIT: begin
            if(vcap_out_done)
                s1_next = S1_IDLE;
            else
                s1_next = S1_WAIT;
        end
        default: begin
            s1_next = 'bx;
        end
    endcase
end

always @(posedge aclk)
begin
    case(s1_next)
        S1_IDLE: begin
            output_trigger <= 1'b0;
        end
        S1_STROBE: begin
            output_trigger <= 1'b1;
        end
        S1_WAIT: begin
            output_trigger <= 1'b0;
        end
    endcase
end

endmodule
