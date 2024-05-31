module timing_controller(
    input   aclk,
    input   aresetn,

    input  [31:0] FRAME_PERIOD,
    input  [31:0] EXPOSURE_0,
    input  [31:0] EXPOSURE_1,
    input  [31:0] EXPOSURE_2,
    input  [31:0] STROBE_PERIOD,
    input  [31:0] STROBE_WIDTH,
    input  exposure_enable,
    input  trigger_enable,

    output  strobe_enable,
    output  [2:0] sensor_trigger,
    input   [1:0] sensor_monitor,
    input   external_trigger,

    input   tick_us,
    input   tick_sec
);

////////////////////////////////////////////////////////////////////////////////
// Exposure Timing Diagram
// PPS or Trig.: __|--|______________________________________________________
// frame period: -->|<----------------frame 1---------------->|<----frame2---
// trigger0    : ___|--------exposure 0-----------|___________|--------------
// trigger1    : ___|----exposure 1----|______________________|--------------
// trigger2    : ___|-------exposure 2------|_________________|--------------
// strobe      : ___|---------|_____|---------|_______________|--------------
//                   <---period---->
//                   <-width->
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// frame timing
// a free-running timer that keeps synchronized with PPS trigger
// time unit is us
reg [31:0] frame_timer;
wire free_run_start = frame_timer==1;
always @(posedge aclk, negedge aresetn)
begin
    if(!aresetn)
        frame_timer <= 0;
    else if(tick_sec) // synchronize with PPS
        frame_timer <= 0;
    else if(tick_us) begin
        if(frame_timer+1>=FRAME_PERIOD)
            frame_timer <= 0;
        else
            frame_timer <= frame_timer+1;
    end
end

////////////////////////////////////////////////////////////////////////////////
// external trigger
(* ASYNC_REG = "TRUE" *)
reg [2:0] ext_trig_sync;
always @(posedge aclk)
begin
    ext_trig_sync <= {ext_trig_sync, external_trigger};
end
wire ext_trig_start = !ext_trig_sync[2] && ext_trig_sync[1];

////////////////////////////////////////////////////////////////////////////////
// exposure timing
// a seperature timer required to eliminate PPS caused glitch
// and keep exposure time constant
reg [31:0] exp_timer;
reg [31:0] exp_0;
reg [31:0] exp_1;
reg [31:0] exp_2;
wire exposure_start = trigger_enable ? ext_trig_start : free_run_start;
always @(posedge aclk)
begin
    if(!exposure_enable) begin
        exp_timer <= 0;
        exp_0 <= 0;
        exp_1 <= 0;
        exp_2 <= 0;
    end
    else if(exp_timer == exp_0) begin // only update period after previous cycle finished
        if(exposure_start) begin
            exp_timer <= 0;
            exp_0 <= EXPOSURE_0;
            exp_1 <= EXPOSURE_1;
            exp_2 <= EXPOSURE_2;
        end
        // else NOP
    end
    else if(tick_us) begin
        exp_timer <= exp_timer+1;
    end
end

reg [2:0] sensor_trigger_r;
always @(posedge aclk)
begin
    sensor_trigger_r[0] <= exp_timer < exp_0;
    sensor_trigger_r[1] <= exp_timer < exp_1;
    sensor_trigger_r[2] <= exp_timer < exp_2;
end
assign sensor_trigger = sensor_trigger_r;

////////////////////////////////////////////////////////////////////////////////
// strobe light timing
reg [31:0] strobe_timer;
wire strobe_tick = tick_us && strobe_timer+1>=STROBE_PERIOD;

// NOTE: to use monitor[0], reg.192[13:11] must be 0x1 or 0x2 
// otherwise use trigger[0] instead
//wire exposure_on = sensor_monitor[0];
wire exposure_on = sensor_trigger[0];
always @(posedge aclk)
begin
    if(!exposure_on) 
        strobe_timer <= 'b0;
    else if(strobe_tick)
        strobe_timer <= 'b0;
    else if(tick_us)
        strobe_timer <= strobe_timer+1;
end

reg strobe_enable_r;
always @(posedge aclk)
begin
    if(!exposure_on)
        strobe_enable_r <= 1'b0;
    else
        strobe_enable_r <= strobe_timer < STROBE_WIDTH;
end
assign strobe_enable = strobe_enable_r;

endmodule
