module precise_timing(
	input aclk,
	input aresetn,

    // synchronizing
    input [31:0] time_strobe_sec,
    input [31:0] time_strobe_ns,
    input time_strobe,

    // real time output
	output reg tick_sec,
    output reg tick_ms,
	output reg tick_us,
    output reg [31:0] time_sec, // second
    output reg [31:0] time_ns // sub-second in ns
);
parameter CLK_PERIOD_NS = 10;
localparam PRESCALE_US_CYCLES = 1000/CLK_PERIOD_NS;

(* ASYNC_REG = "TRUE" *)
reg [2:0] time_strobe_reg;
wire time_strobe_sync = ~time_strobe_reg[2] & time_strobe_reg[1];
always @(posedge aclk)
begin
    time_strobe_reg <= {time_strobe_reg, time_strobe};
end

// time_ns is a master counter and will be sychronized
// upon time_strobe
wire sec_end = time_ns+CLK_PERIOD_NS >= 1_000_000_000;
always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        time_ns <= 0;
    end
    else if(time_strobe_sync) begin
        time_ns <= time_strobe_ns;
    end
    else if(sec_end)begin
        time_ns <= 0;
    end
    else begin
        time_ns <= time_ns+CLK_PERIOD_NS;
    end
end

// time_sec is a master counter and will be sychronized
// upon time_strobe
always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn) begin
        time_sec <= 0;
    end
    else if(time_strobe_sync) begin
        time_sec <= time_strobe_sec;
    end
    else if(sec_end) begin
        time_sec <= time_sec+1;
    end
end

// ms_counter and us_counter only synchronize with sec_end
reg [19:0] ms_counter;
wire ms_end = ms_counter+CLK_PERIOD_NS >= 1_000_000;
always @(posedge aclk)
begin
    if(sec_end || ms_end) begin
        ms_counter <= 0;
    end
    else begin
        ms_counter <= ms_counter + CLK_PERIOD_NS;
    end
end

reg [9:0] us_counter;
wire us_end = us_counter+CLK_PERIOD_NS >= 1_000;
always @(posedge aclk)
begin
    if(sec_end || us_end) begin
        us_counter <= 0;
    end
    else begin
        us_counter <= us_counter + CLK_PERIOD_NS;
    end
end

always @(posedge aclk)
begin
    tick_sec <= sec_end;
    tick_ms <= ms_end;
    tick_us <= us_end;
end
endmodule
