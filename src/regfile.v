module regfile(
    input   aclk,
    input   aresetn,

    input   [7:0] s_axi_awaddr,
    input   s_axi_awvalid,
    output  s_axi_awready,

    input   [31:0] s_axi_wdata,
    input   [3:0] s_axi_wstrb,
    input   s_axi_wvalid,
    output  s_axi_wready,

    output  [1:0] s_axi_bresp,
    output  s_axi_bvalid,
    input   s_axi_bready,

    input   [7:0] s_axi_araddr,
    input   s_axi_arvalid,
    output  s_axi_arready,

    output  [31:0] s_axi_rdata,
    output  [1:0] s_axi_rresp,
    output  s_axi_rvalid,
    input   s_axi_rready,

    // software reset output
    output  soft_reset,

    // SPI controller
    output  spi_start,
    output  [8:0] spi_addr,
    output  spi_rdwr,
    output  [15:0] spi_wdata,
    input   [15:0] spi_rdata,
    input   spi_ready,

    // camera timing control
    output  [31:0] FRAME_PERIOD,
    output  [31:0] EXPOSURE_0,
    output  [31:0] EXPOSURE_1,
    output  [31:0] EXPOSURE_2,
    output  [31:0] STROBE_PERIOD,
    output  [31:0] STROBE_WIDTH,
    output  exposure_enable,
    output  trigger_enable,

    // camera interface
    output  serdes_enable,
    input   serdes_locked,
    output  subsample,

    // VCAP control
    output  [31:0] IMG_DMA_ADDR0,
    output  [31:0] IMG_DMA_ADDR1,
    output  vcap_enable,
    input   vcap_current,
    input   vcap_in_done,
    input   vcap_out_done,
    input   [15:0] vcap_width,
    input   [15:0] vcap_height,

    // TAG control
    output  [31:0] TAG_DMA_ADDR0,
    output  [31:0] TAG_DMA_ADDR1,
    output  tag_enable,
    input   tag_current,
    input   tag_in_done,

    // GVSP stream 0 control
    output  [15:0] SC0_PACKET_DELAY,
    output  [47:0] SC0_DST_MAC,
    output  [47:0] SC0_SRC_MAC,
    output  [31:0] SC0_DST_IP,
    output  [31:0] SC0_SRC_IP,
    output  [15:0] SC0_DST_PORT,
    output  [15:0] SC0_SRC_PORT,

    // GVSP stream 1 control
    output  [15:0] SC1_PACKET_DELAY,
    output  [47:0] SC1_DST_MAC,
    output  [47:0] SC1_SRC_MAC,
    output  [31:0] SC1_DST_IP,
    output  [31:0] SC1_SRC_IP,
    output  [15:0] SC1_DST_PORT,
    output  [15:0] SC1_SRC_PORT,

    // Image format
    output  [31:0] PIXEL_TYPE,

    // CLC LUT access
    output  [31:0] clc_addr,
    output  [31:0] clc_wdata,
    output  clc_wen,
    input   [31:0] clc_rdata,

    // upstream interrupt request
    // TODO: do we need a dedicated interrupt controller?
    output  irq_request,

    // Stepper control
    output  stepper_enable,
    output  stepper_direction,
    output  stepper_step,
    output  [15:0] stepper_pwm_cycle,
    output  [15:0] stepper_pwm_duty,

    // RTC control
    output  [31:0] time_strobe_sec,
    output  [31:0] time_strobe_ns,
    output  time_strobe,
    input   [31:0] time_sec,
    input   [31:0] time_ns
);
parameter CLK_PERIOD_NS = 10;
localparam PRESCALE_US_CYCLES = 1000/CLK_PERIOD_NS;

localparam GEV_PIXEL_FORMAT_MONO8 = 32'h01080001;

////////////////////////////////////////////////////////////////////////////////
// AXI lite state machine
wire [7:0] wr_addr;
wire [31:0] wr_dout;
wire [3:0] wr_be;
wire wr_en;
wire [7:0] rd_addr;
wire rd_en;
reg [31:0] rd_din;

axi_lite_to_mm #(
    .ADDR_BITS(8),
    .DATA_BITS(32)
) axi_lite_to_mm_0(
    .s_axi_aclk(aclk),
    .s_axi_aresetn(aresetn),
    
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),

    .wr_addr(wr_addr),
    .wr_dout(wr_dout),
    .wr_be(wr_be),
    .wr_en(wr_en),
    .wr_ready(1'b1),

    .rd_addr(rd_addr),
    .rd_din(rd_din),
    .rd_en(rd_en),
    .rd_ready(1'b1)
);

////////////////////////////////////////////////////////////////////////////////
//
(* ASYNC_REG = "TRUE" *)
reg [1:0] serdes_locked_sync;
always @(posedge aclk)
begin
    serdes_locked_sync <= {serdes_locked_sync, serdes_locked};
end
wire serdes_locked_s = serdes_locked_sync[1];

////////////////////////////////////////////////////////////////////////////////
// register file
reg [31:0] reg_ctrl;
reg [31:0] reg_cmd;
reg [31:0] reg_frame_period;
reg [31:0] reg_exposure_0;
reg [31:0] reg_exposure_1;
reg [31:0] reg_exposure_2;
reg [31:0] reg_strobe_period;
reg [31:0] reg_strobe_width;
reg [31:0] reg_vcap_address0;
reg [31:0] reg_vcap_address1;
reg [31:0] reg_sc0_src_mac_low;
reg [31:0] reg_sc0_src_mac_high;
reg [31:0] reg_sc0_dst_mac_low;
reg [31:0] reg_sc0_dst_mac_high;
reg [31:0] reg_sc0_src_ip;
reg [31:0] reg_sc0_dst_ip;
reg [31:0] reg_sc0_port;
reg [31:0] reg_sc0_delay;
reg [31:0] reg_sc1_src_mac_low;
reg [31:0] reg_sc1_src_mac_high;
reg [31:0] reg_sc1_dst_mac_low;
reg [31:0] reg_sc1_dst_mac_high;
reg [31:0] reg_sc1_src_ip;
reg [31:0] reg_sc1_dst_ip;
reg [31:0] reg_sc1_port;
reg [31:0] reg_sc1_delay;
reg [31:0] reg_tag_address0;
reg [31:0] reg_tag_address1;
reg [31:0] reg_pixel_type;
reg [31:0] reg_time_sec;
reg [31:0] reg_time_ns;
reg [31:0] reg_stepper;
reg [31:0] reg_pwm;
reg [31:0] reg_clc_addr;
reg [31:0] reg_clc_data;

assign soft_reset = reg_ctrl[0];
assign serdes_enable = reg_ctrl[1];
assign subsample = reg_ctrl[2];
assign exposure_enable = reg_ctrl[8];
assign trigger_enable = reg_ctrl[9];
assign vcap_enable = reg_ctrl[16];
assign tag_enable = reg_ctrl[24];

wire serdes_locked_ie = reg_ctrl[4];
wire spi_ready_ie = reg_ctrl[7];
wire vcap_in_done_ie = reg_ctrl[20];
wire vcap_out_done_ie = reg_ctrl[22];
wire tag_in_done_ie = reg_ctrl[28];

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        reg_ctrl <= 'b0;
        reg_cmd <= 'b0;
        reg_frame_period <= 0;
        reg_exposure_0 <= 0;
        reg_exposure_1 <= 0;
        reg_exposure_2 <= 0;
        reg_strobe_period <= 0;
        reg_strobe_width <= 0;
        reg_vcap_address0 <= 0;
        reg_vcap_address1 <= 0;
        reg_sc0_src_mac_low <= 0;
        reg_sc0_src_mac_high <= 0;
        reg_sc0_dst_mac_low <= 0;
        reg_sc0_dst_mac_high <= 0;
        reg_sc0_src_ip <= 0;
        reg_sc0_dst_ip <= 0;
        reg_sc0_port <= 0;
        reg_sc0_delay <= 0;
        reg_sc1_src_mac_low <= 0;
        reg_sc1_src_mac_high <= 0;
        reg_sc1_dst_mac_low <= 0;
        reg_sc1_dst_mac_high <= 0;
        reg_sc1_src_ip <= 0;
        reg_sc1_dst_ip <= 0;
        reg_sc1_port <= 0;
        reg_sc1_delay <= 0;
        reg_tag_address0 <= 0;
        reg_tag_address1 <= 0;
        reg_pixel_type <= GEV_PIXEL_FORMAT_MONO8;
        reg_time_sec <= 0;
        reg_time_ns <= 0;
        reg_stepper <= 0;
        reg_pwm <= {16'd2000,16'd1000};
    end
    else if(wr_en) begin
        case(wr_addr[7:2])
            // global control
            0: begin 
                if(wr_be[0]) reg_ctrl[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_ctrl[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_ctrl[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_ctrl[31:24] <= wr_dout[31:24];
            end
            1: begin 
            end
            2: begin
                if(wr_be[0]) reg_cmd[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_cmd[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_cmd[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_cmd[31:24] <= wr_dout[31:24];
            end
            3: begin
            end
            // exposure control
            4: begin
                if(wr_be[0]) reg_frame_period[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_frame_period[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_frame_period[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_frame_period[31:24] <= wr_dout[31:24];
            end
            5: begin
                if(wr_be[0]) reg_exposure_0[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_exposure_0[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_exposure_0[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_exposure_0[31:24] <= wr_dout[31:24];
            end
            6: begin
                if(wr_be[0]) reg_exposure_1[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_exposure_1[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_exposure_1[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_exposure_1[31:24] <= wr_dout[31:24];
            end
            7: begin
                if(wr_be[0]) reg_exposure_2[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_exposure_2[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_exposure_2[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_exposure_2[31:24] <= wr_dout[31:24];
            end
            // strobe control
            8: begin
                if(wr_be[0]) reg_strobe_period[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_strobe_period[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_strobe_period[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_strobe_period[31:24] <= wr_dout[31:24];
            end
            9: begin
                if(wr_be[0]) reg_strobe_width[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_strobe_width[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_strobe_width[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_strobe_width[31:24] <= wr_dout[31:24];
            end
            // 10,11: reserved for strobe control
            // capture control
            12: begin
                if(wr_be[0]) reg_vcap_address0[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_vcap_address0[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_vcap_address0[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_vcap_address0[31:24] <= wr_dout[31:24];
            end
            13: begin
                if(wr_be[0]) reg_vcap_address1[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_vcap_address1[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_vcap_address1[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_vcap_address1[31:24] <= wr_dout[31:24];
            end
            // 14: STREAM_PERIOD (obsolete)
            // 15: captured image size
            // stream CH0 control
            16: begin
                if(wr_be[0]) reg_sc0_src_mac_low[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_src_mac_low[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_src_mac_low[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_src_mac_low[31:24] <= wr_dout[31:24];
            end
            17: begin
                if(wr_be[0]) reg_sc0_src_mac_high[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_src_mac_high[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_src_mac_high[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_src_mac_high[31:24] <= wr_dout[31:24];
            end
            18: begin
                if(wr_be[0]) reg_sc0_dst_mac_low[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_dst_mac_low[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_dst_mac_low[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_dst_mac_low[31:24] <= wr_dout[31:24];
            end
            19: begin
                if(wr_be[0]) reg_sc0_dst_mac_high[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_dst_mac_high[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_dst_mac_high[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_dst_mac_high[31:24] <= wr_dout[31:24];
            end
            20: begin
                if(wr_be[0]) reg_sc0_src_ip[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_src_ip[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_src_ip[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_src_ip[31:24] <= wr_dout[31:24];
            end
            21: begin
                if(wr_be[0]) reg_sc0_dst_ip[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_dst_ip[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_dst_ip[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_dst_ip[31:24] <= wr_dout[31:24];
            end
            22: begin
                if(wr_be[0]) reg_sc0_port[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_port[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_port[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_port[31:24] <= wr_dout[31:24];
            end
            23: begin
                if(wr_be[0]) reg_sc0_delay[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc0_delay[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc0_delay[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc0_delay[31:24] <= wr_dout[31:24];
            end
            24: begin
                if(wr_be[0]) reg_sc1_src_mac_low[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_src_mac_low[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_src_mac_low[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_src_mac_low[31:24] <= wr_dout[31:24];
            end
            25: begin
                if(wr_be[0]) reg_sc1_src_mac_high[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_src_mac_high[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_src_mac_high[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_src_mac_high[31:24] <= wr_dout[31:24];
            end
            26: begin
                if(wr_be[0]) reg_sc1_dst_mac_low[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_dst_mac_low[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_dst_mac_low[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_dst_mac_low[31:24] <= wr_dout[31:24];
            end
            27: begin
                if(wr_be[0]) reg_sc1_dst_mac_high[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_dst_mac_high[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_dst_mac_high[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_dst_mac_high[31:24] <= wr_dout[31:24];
            end
            28: begin
                if(wr_be[0]) reg_sc1_src_ip[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_src_ip[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_src_ip[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_src_ip[31:24] <= wr_dout[31:24];
            end
            29: begin
                if(wr_be[0]) reg_sc1_dst_ip[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_dst_ip[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_dst_ip[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_dst_ip[31:24] <= wr_dout[31:24];
            end
            30: begin
                if(wr_be[0]) reg_sc1_port[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_port[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_port[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_port[31:24] <= wr_dout[31:24];
            end
            31: begin
                if(wr_be[0]) reg_sc1_delay[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_sc1_delay[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_sc1_delay[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_sc1_delay[31:24] <= wr_dout[31:24];
            end
            32: begin
                if(wr_be[0]) reg_tag_address0[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_tag_address0[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_tag_address0[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_tag_address0[31:24] <= wr_dout[31:24];
            end
            33: begin
                if(wr_be[0]) reg_tag_address1[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_tag_address1[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_tag_address1[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_tag_address1[31:24] <= wr_dout[31:24];
            end
            //34,35: reserved for tag dma control
            36: begin
                if(wr_be[0]) reg_pixel_type[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_pixel_type[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_pixel_type[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_pixel_type[31:24] <= wr_dout[31:24];
            end
            48: begin
                if(wr_be[0]) reg_time_sec[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_time_sec[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_time_sec[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_time_sec[31:24] <= wr_dout[31:24];
            end
            49: begin
                if(wr_be[0]) reg_time_ns[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_time_ns[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_time_ns[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_time_ns[31:24] <= wr_dout[31:24];
            end
            52: begin
                if(wr_be[0]) reg_stepper[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_stepper[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_stepper[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_stepper[31:24] <= wr_dout[31:24];
            end
            53: begin
                if(wr_be[0]) reg_pwm[7:0] <= wr_dout[7:0];
                if(wr_be[1]) reg_pwm[15:8] <= wr_dout[15:8];
                if(wr_be[2]) reg_pwm[23:16] <= wr_dout[23:16];
                if(wr_be[3]) reg_pwm[31:24] <= wr_dout[31:24];
            end
            56: begin
            end
            57: begin
            end
        endcase
    end
end

always @(*)
begin
    case(rd_addr[7:2])
        0: rd_din = {3'b0, tag_in_done_ie, 3'b0, tag_enable,
            1'b0, vcap_out_done_ie,1'b0, vcap_in_done_ie, 3'b0, vcap_enable, 
            6'b0, trigger_enable, exposure_enable, 
            spi_ready_ie, 2'b0, serdes_locked_ie, 1'b0, subsample, serdes_enable, soft_reset};
        1: rd_din = {2'b0, tag_current, tag_in_done, 3'b0, tag_enable, 
            1'b0, vcap_out_done, vcap_current, vcap_in_done, 3'b0, vcap_enable,
            6'b0, trigger_enable, exposure_enable, 
            spi_ready, 2'b0, serdes_locked_s, 1'b0, subsample, serdes_enable, soft_reset};
        2: rd_din = {spi_ready, spi_rdwr, 5'b0, spi_addr, spi_wdata};
        3: rd_din = {spi_ready, spi_rdwr, 5'b0, spi_addr, spi_rdata};
        4: rd_din = reg_frame_period;
        5: rd_din = reg_exposure_0;
        6: rd_din = reg_exposure_1;
        7: rd_din = reg_exposure_2;
        8: rd_din = reg_strobe_period;
        9: rd_din = reg_strobe_width;
        //10,11:
        12: rd_din = reg_vcap_address0;
        13: rd_din = reg_vcap_address1;
        15: rd_din = {vcap_height, vcap_width};
        16: rd_din = reg_sc0_src_mac_low;
        17: rd_din = {16'b0, reg_sc0_src_mac_high[15:0]};
        18: rd_din = reg_sc0_dst_mac_low;
        19: rd_din = {16'b0, reg_sc0_dst_mac_high[15:0]};
        20: rd_din = reg_sc0_src_ip;
        21: rd_din = reg_sc0_dst_ip;
        22: rd_din = reg_sc0_port;
        23: rd_din = {16'b0, reg_sc0_delay[15:0]};
        24: rd_din = reg_sc1_src_mac_low;
        25: rd_din = {16'b0, reg_sc1_src_mac_high[15:0]};
        26: rd_din = reg_sc1_dst_mac_low;
        27: rd_din = {16'b0, reg_sc1_dst_mac_high[15:0]};
        28: rd_din = reg_sc1_src_ip;
        29: rd_din = reg_sc1_dst_ip;
        30: rd_din = reg_sc1_port;
        31: rd_din = {16'b0, reg_sc1_delay[15:0]};
        32: rd_din = reg_tag_address0;
        33: rd_din = reg_tag_address1;
        //34,35
        36: rd_din = reg_pixel_type;
        48: rd_din = time_sec;
        49: rd_din = time_ns;
        52: rd_din = reg_stepper;
        53: rd_din = reg_pwm;
        56: rd_din = reg_clc_addr;
        57: rd_din = reg_clc_data;
        default: rd_din = 'bx;
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// bypass output

assign FRAME_PERIOD = reg_frame_period;
assign EXPOSURE_0 = reg_exposure_0;
assign EXPOSURE_1 = reg_exposure_1;
assign EXPOSURE_2 = reg_exposure_2;
assign STROBE_PERIOD = reg_strobe_period;
assign STROBE_WIDTH = reg_strobe_width;

assign IMG_DMA_ADDR0 = reg_vcap_address0;
assign IMG_DMA_ADDR1 = reg_vcap_address1;

assign SC0_PACKET_DELAY = reg_sc0_delay[15:0];
assign SC0_DST_MAC = {reg_sc0_dst_mac_high, reg_sc0_dst_mac_low};
assign SC0_SRC_MAC = {reg_sc0_src_mac_high, reg_sc0_src_mac_low};
assign SC0_DST_IP = reg_sc0_dst_ip;
assign SC0_SRC_IP = reg_sc0_src_ip;
assign SC0_DST_PORT = reg_sc0_port[31:16];
assign SC0_SRC_PORT = reg_sc0_port[15:0];

assign SC1_PACKET_DELAY = reg_sc1_delay[15:0];
assign SC1_DST_MAC = {reg_sc1_dst_mac_high, reg_sc1_dst_mac_low};
assign SC1_SRC_MAC = {reg_sc1_src_mac_high, reg_sc1_src_mac_low};
assign SC1_DST_IP = reg_sc1_dst_ip;
assign SC1_SRC_IP = reg_sc1_src_ip;
assign SC1_DST_PORT = reg_sc1_port[31:16];
assign SC1_SRC_PORT = reg_sc1_port[15:0];

assign TAG_DMA_ADDR0 = reg_tag_address0;
assign TAG_DMA_ADDR1 = reg_tag_address1;

assign PIXEL_TYPE = reg_pixel_type;

////////////////////////////////////////////////////////////////////////////////
// Realtime Timer
assign time_strobe_sec = reg_time_sec;
assign time_strobe_ns = reg_time_ns;

reg time_strobe_sync;
always @(posedge aclk)
begin
    time_strobe_sync <= (wr_en && wr_addr[7:2]==48);
end
assign time_strobe = time_strobe_sync;

////////////////////////////////////////////////////////////////////////////////
// Interrput
wire [7:0] intr_trigger = {
    tag_in_done, vcap_out_done, vcap_in_done, spi_ready, serdes_locked_s};
wire [7:0] intr_enable = {
    tag_in_done_ie, vcap_out_done_ie, vcap_in_done_ie, spi_ready_ie, serdes_locked_ie};
reg [7:0] intr_state;
always @(posedge aclk)
begin
    intr_state <= intr_trigger;
end
reg irq_request_r;
always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        irq_request_r <= 1'b0;
    end
    else begin
        irq_request_r <= |((intr_state^8'hFF)&intr_trigger&intr_enable); // rise_edge
    end
end
assign irq_request = irq_request_r;

////////////////////////////////////////////////////////////////////////////////
// for SPI controller
reg spi_start_r;
always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        spi_start_r <= 1'b0;
    end
    else if(wr_en && wr_addr[7:2]==2 && wr_be[3]) begin
        spi_start_r <= 1'b1;
    end
    else begin
        spi_start_r <= 1'b0;
    end
end

assign spi_wdata = reg_cmd[15:0];
assign spi_addr = reg_cmd[24:16];
assign spi_rdwr = reg_cmd[30];
assign spi_start = spi_start_r;

////////////////////////////////////////////////////////////////////////////////
// Colomn LUT access
wire [31:0] clc_dout;
indirect_access clc_lut_if_0(
    .aclk(aclk),
    .aresetn(aresetn),
    .wr_sel(wr_addr[2]),
    .wr_be(wr_be),
    .wr_en(wr_en && (wr_addr[7:2]==56||wr_addr[7:2]==57)),
    .wr_din(wr_dout),
    .rd_sel(rd_addr[2]),
    .rd_en(rd_en && (rd_addr[7:2]==56||rd_addr[7:2]==57)),
    .rd_dout(clc_dout),
    .addr_o(clc_addr),
    .data_o(clc_wdata),
    .data_i(clc_rdata),
    .we_o(clc_wen),
    .re_o()
);

always @(*)
begin
    reg_clc_addr = clc_dout;
    reg_clc_data = clc_dout;
end

////////////////////////////////////////////////////////////////////////////////
// Stepper
// reg_stepper[8] - step
// reg_stepper[1] - dir
// reg_stepper[0] - enable
reg stepper_step_r;
always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        stepper_step_r <= 1'b0;
    end
    else if(wr_en && wr_addr[7:2]==52 && wr_be[1] && wr_dout[8]) begin
        stepper_step_r <= 1'b1;
    end
    else begin
        stepper_step_r <= 1'b0;
    end
end
assign stepper_enable = reg_stepper[0];
assign stepper_direction = reg_stepper[1];
assign stepper_step = stepper_step_r;
assign stepper_pwm_cycle = reg_pwm[31:16];
assign stepper_pwm_duty = reg_pwm[15:0];

endmodule
