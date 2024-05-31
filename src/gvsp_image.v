module gvsp_image #(
    parameter DATA_BITS=32
) (
    input aclk,
    input aresetn,

    input enable,
    // timing
    input [15:0] PACKET_DELAY, // inter-packet delay in us
    input tick_us, // tick per microsecond

    // meta data
    input [15:0] hsize,
    input [15:0] vsize,
    input [63:0] timestamp,
    input [31:0] pixel_type,
    input end_of_frame,

    // image data
    input [DATA_BITS-1:0] s_axis_tdata,
    input s_axis_tvalid,
    input s_axis_tlast,
    input [0:0] s_axis_tuser, // start-of-frame
    output s_axis_tready,

    // gvsp packet
    output [7:0] m_axis_tdata,
    output m_axis_tvalid,
    output m_axis_tlast,
    input m_axis_tready,

    output block_done
);

localparam GVSP_HEADER_LENGTH = 8;
localparam GVSP_LEADER_LENGTH = 44;
localparam GVSP_TRAILER_LENGTH = 16;
localparam GVSP_LEADER_FORMAT = 1;
localparam GVSP_TRAILER_FORMAT = 2;
localparam GVSP_DATA_FORMAT = 3;
localparam GVSP_PAYLOAD_TYPE_IMAGE = 1;

reg [5:0] count;
reg [15:0] block_id;
reg [23:0] packet_id;
reg [DATA_BITS-1:0] s1_tdata;
reg s1_tready;
reg s1_tvalid;
reg s1_tlast;
reg s1_last_r;
reg [DATA_BITS-1:0] s1_data_r;
reg s1_end_of_frame;
reg [15:0] delay_cnt;

assign s_axis_tready = s1_tready;
assign m_axis_tdata = s1_tdata;
assign m_axis_tvalid = s1_tvalid;
assign m_axis_tlast = s1_tlast;
assign block_done = s1_end_of_frame;

integer s1, s1_next;
localparam S1_IDLE=0, S1_LEADER=1, S1_DELAY=2, S1_DATA_HDR=3, S1_DATA_FETCH=4, 
    S1_DATA_STROBE=5, S1_DATA_ACK=6, S1_TRAILER=7, S1_END=8, S1_DISCARD=9;

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
            if(s_axis_tvalid)
                if(enable)
                    s1_next = S1_LEADER;
                else
                    s1_next = S1_DISCARD;
            else
                s1_next = S1_IDLE;
        end
        S1_LEADER: begin
            if(m_axis_tlast && m_axis_tready)
                s1_next = S1_DELAY;
            else
                s1_next = S1_LEADER;
        end
        S1_DELAY: begin
            if(delay_cnt >= PACKET_DELAY)
                if(!s_axis_tvalid && end_of_frame)
                    s1_next = S1_TRAILER;
                else
                    s1_next = S1_DATA_HDR;
            else
                s1_next = S1_DELAY;
        end
        S1_DATA_HDR: begin
            if(m_axis_tready && count==GVSP_HEADER_LENGTH-1)
                s1_next = S1_DATA_FETCH;
            else
                s1_next = S1_DATA_HDR;
        end
        S1_DATA_FETCH: begin
            if(s_axis_tvalid)
                s1_next = S1_DATA_STROBE;
            else
                s1_next = S1_DATA_FETCH;
        end
        S1_DATA_STROBE: begin
            s1_next = S1_DATA_ACK;
        end
        S1_DATA_ACK: begin
            if(m_axis_tready && count==(DATA_BITS/8-1))
                if(m_axis_tlast)
                    s1_next = S1_DELAY;
                else
                    s1_next = S1_DATA_FETCH;
            else
                s1_next = S1_DATA_ACK;
        end
        S1_TRAILER: begin
            if(m_axis_tlast && m_axis_tready)
                s1_next = S1_END;
            else
                s1_next = S1_TRAILER;
        end
        S1_END: begin
            s1_next = S1_IDLE;
        end
        S1_DISCARD: begin
            if(end_of_frame)
                s1_next = S1_IDLE;
            else
                s1_next = S1_DISCARD;
        end
        default: begin
            s1_next = 'bx;
        end
    endcase
end

always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        s1_tready <= 1'b0;
        s1_tvalid <= 1'b0;
        s1_tlast <= 1'b0;
        s1_last_r <= 1'b0;
        s1_data_r <= 'bx;
        s1_end_of_frame <= 1'b0;
        count <= 'bx;
        delay_cnt <= 'bx;
        block_id <= 0; 
    end
    else case(s1_next)
        S1_IDLE: begin
            count <= 0;
            if(block_id==0)
                block_id <= block_id+1; // block_id always starts from 1
            s1_tready <= 1'b0;
        end
        S1_LEADER: begin
            s1_end_of_frame <= 1'b0;
            s1_tvalid <= 1'b1;
            if(s1_tvalid && m_axis_tready) begin
                if(count == GVSP_LEADER_LENGTH-2)
                    s1_tlast <= 1'b1;
                count <= count+1;
            end
            delay_cnt <= 0;
        end
        S1_DELAY: begin
            s1_tvalid <= 1'b0;
            s1_tlast <= 1'b0;
            if(tick_us)
                delay_cnt <= delay_cnt+1;
            count <= 0;
        end
        S1_DATA_HDR: begin
            s1_tvalid <= 1'b1;
            if(s1_tvalid && m_axis_tready) begin
                count <= count+1;
            end
            delay_cnt <= 0;
        end
        S1_DATA_FETCH: begin
            s1_tready <= 1'b1;
            s1_tvalid <= 1'b0;
            s1_tlast <= 1'b0;
            count <= 0;
        end
        S1_DATA_STROBE: begin
            s1_tready <= 1'b0;
            s1_tvalid <= 1'b1;
            s1_last_r <= s_axis_tlast;
            s1_data_r <= s_axis_tdata;
        end
        S1_DATA_ACK: begin
            if(m_axis_tready) begin
                if(count==(DATA_BITS/8-2))
                    s1_tlast <= s1_last_r;
                count <= count+1;
                s1_data_r <= s1_data_r[DATA_BITS-1:8];
            end
        end
        S1_TRAILER: begin
            s1_tvalid <= 1'b1;
            if(s1_tvalid && m_axis_tready) begin
                if(count == GVSP_TRAILER_LENGTH-2)
                    s1_tlast <= 1'b1;
                count <= count+1;
            end
        end
        S1_END: begin
            s1_tvalid <= 1'b0;
            s1_tlast <= 1'b0;
            s1_end_of_frame <= 1'b1;
            block_id <= block_id+1;
        end
        S1_DISCARD: begin
            s1_tready <= 1'b1;
        end
    endcase
end

always @(*)
begin
    case(s1)
        S1_LEADER: begin
            case(count)
                0,1: s1_tdata = 0; // status==SUCCESS
                2: s1_tdata = block_id[15:8];
                3: s1_tdata = block_id[7:0];
                4: s1_tdata = GVSP_LEADER_FORMAT;
                5: s1_tdata = packet_id[23:16]; // packet_id
                6: s1_tdata = packet_id[15:8]; // packet_id
                7: s1_tdata = packet_id[7:0]; // packet_id
                8,9: s1_tdata = 0; // reserved
                10: s1_tdata = GVSP_PAYLOAD_TYPE_IMAGE[15:8];
                11: s1_tdata = GVSP_PAYLOAD_TYPE_IMAGE[7:0];
                12: s1_tdata = timestamp[63:56];
                13: s1_tdata = timestamp[55:48];
                14: s1_tdata = timestamp[47:40];
                15: s1_tdata = timestamp[39:32];
                16: s1_tdata = timestamp[31:24];
                17: s1_tdata = timestamp[23:16];
                18: s1_tdata = timestamp[15:8];
                19: s1_tdata = timestamp[7:0];
                20: s1_tdata = pixel_type[31:24];
                21: s1_tdata = pixel_type[23:16];
                22: s1_tdata = pixel_type[15:8];
                23: s1_tdata = pixel_type[7:0];
                24,25: s1_tdata = 0; // size x[31:16]
                26: s1_tdata = hsize[15:8]; // size x[15:8]
                27: s1_tdata = hsize[7:0]; // size x[15:8]
                28,29: s1_tdata = 0; // size y[31:16]
                30: s1_tdata = vsize[15:8]; // size y[15:8]
                31: s1_tdata = vsize[7:0]; // size y[15:8]
                32,33,34,35,36,37,38,39,40,41,42,43: s1_tdata = 0; // not used
                default: s1_tdata = 'bx;
            endcase
        end
        S1_DATA_HDR: begin
            case(count)
                0,1: s1_tdata = 0; // status==SUCCESS
                2: s1_tdata = block_id[15:8];
                3: s1_tdata = block_id[7:0];
                4: s1_tdata = GVSP_DATA_FORMAT;
                5: s1_tdata = packet_id[23:16]; // packet_id
                6: s1_tdata = packet_id[15:8]; // packet_id
                7: s1_tdata = packet_id[7:0]; // packet_id
                default: s1_tdata = 'bx;
            endcase
        end
        S1_DATA_STROBE, S1_DATA_ACK: begin
            s1_tdata = s1_data_r[7:0];
        end
        S1_TRAILER: begin
            case(count)
                0,1: s1_tdata = 0; // status==SUCCESS
                2: s1_tdata = block_id[15:8];
                3: s1_tdata = block_id[7:0];
                4: s1_tdata = GVSP_TRAILER_FORMAT;
                5: s1_tdata = packet_id[23:16]; // packet_id
                6: s1_tdata = packet_id[15:8]; // packet_id
                7: s1_tdata = packet_id[7:0]; // packet_id
                8,9: s1_tdata = 0; // reserved
                10: s1_tdata = GVSP_PAYLOAD_TYPE_IMAGE[15:8];
                11: s1_tdata = GVSP_PAYLOAD_TYPE_IMAGE[7:0];
                12,13: s1_tdata = 0; // size y[31:16];
                14: s1_tdata = vsize[15:8];
                15: s1_tdata = vsize[7:0];
                default: s1_tdata = 'bx;
            endcase
        end
        default: begin
            s1_tdata = 'bx;
        end
    endcase
end

always @(posedge aclk)
begin
    if(s1_next == S1_IDLE)
        packet_id <= 0;
    else if(m_axis_tvalid && m_axis_tready && m_axis_tlast)
        packet_id <= packet_id+1;
end

endmodule
