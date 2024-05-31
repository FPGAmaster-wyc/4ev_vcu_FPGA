module drv8835_if
(
    input   clk,
    input   rst,

    input   en, // enable driver
    input   dir, // direction
    input   step, // move one step

    input   [15:0] CYCLE_COUNT, // PWM period in clock cycles
    input   [15:0] DUTY_COUNT, // PWM pulse width in clock cycles

    output  drv_a1, // A+
    output  drv_a2, // A-
    output  drv_b1, // B+
    output  drv_b2  // B-
);
/*
* Truth Table for a1,a2 and b1,b2:
* 00 - coast (float); // High-z
* 01 - forward current;
* 10 - reverse current
* 11 - brake (short); // discharge reverse current
*/
parameter DISCHARGE_COUNT = 16'hFFFF;

(* ASYNC_REG = "TRUE" *)
reg [2:0] step_sync;
reg [1:0] phase;
reg [15:0] timer;
reg step_request;
reg a_p, a_n, b_p, b_n;

integer s1, s1_next;
localparam S1_IDLE=0, S1_SETUP=1, S1_ACTIVE=2, S1_PASSIVE=3, S1_DISCHARGE=4;

always @(posedge clk)
begin
    step_sync <= {step_sync, step};
end
wire step_posedge = !step_sync[2] && step_sync[1];

always @(posedge clk, posedge rst)
begin
    if(rst)
        s1 <= S1_IDLE;
    else
        s1 <= s1_next;
end

always @(*)
begin
    case(s1)
        S1_IDLE: begin
            if(en)
                s1_next = S1_ACTIVE;
            else
                s1_next = S1_IDLE;
        end
        S1_SETUP, S1_ACTIVE: begin
            if(timer+1 == CYCLE_COUNT)
                s1_next = S1_SETUP;
            else if(timer == DUTY_COUNT)
                s1_next = S1_PASSIVE;
            else
                s1_next = S1_ACTIVE;
        end
        S1_PASSIVE: begin
            if(timer+1 == CYCLE_COUNT)
                if(en)
                    s1_next = S1_SETUP;
                else
                    s1_next = S1_DISCHARGE;
            else
                s1_next = S1_PASSIVE;
        end
        S1_DISCHARGE: begin
            if(timer+1 == DISCHARGE_COUNT)
                s1_next = S1_IDLE;
            else
                s1_next = S1_DISCHARGE;
        end
        default: begin
            s1_next = 'bx;
        end
    endcase
end

always @(posedge clk)
begin
    if(step_posedge)
        step_request <= 1'b1;
    else if(s1_next == S1_SETUP)
        step_request <= 1'b0;
end

always @(posedge clk)
begin
    if(s1_next == S1_IDLE || s1_next == S1_SETUP)
        timer <= 'b0;
    else
        timer <= timer+1;
end

always @(posedge clk, posedge rst)
begin
    if(rst) begin
        {a_p, a_n, b_p, b_n} <= 4'b0000;
        phase <= 'b0;
    end
    else case(s1_next)
        S1_IDLE: begin
            {a_p, a_n, b_p, b_n} <= 4'b0000;
        end
        S1_SETUP: begin
            if(step_request)
                if(dir)
                    phase <= phase-1;
                else
                    phase <= phase+1;
        end
        S1_ACTIVE: begin
            case(phase)
                0: {a_p, a_n, b_p, b_n} <= 4'b1010;
                1: {a_p, a_n, b_p, b_n} <= 4'b0110;
                2: {a_p, a_n, b_p, b_n} <= 4'b0101;
                3: {a_p, a_n, b_p, b_n} <= 4'b1001;
            endcase
        end
        S1_PASSIVE, S1_DISCHARGE: begin
            {a_p, a_n, b_p, b_n} <= 4'b1111;
        end
    endcase
end

assign drv_a1 = a_p;
assign drv_a2 = a_n;
assign drv_b1 = b_p;
assign drv_b2 = b_n;

endmodule
