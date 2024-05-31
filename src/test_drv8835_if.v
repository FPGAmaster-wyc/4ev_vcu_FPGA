module test_drv8835_if;

reg aclk, areset;
reg stepper_enable;
reg stepper_direction;
reg stepper_step;

reg [15:0] stepper_pwm_cycle;
reg [15:0] stepper_pwm_duty;

wire drv_ain1, drv_ain2, drv_bin1, drv_bin2;


drv8835_if drv8835_if_i(
    .clk(aclk),
    .rst(areset),
    .en(stepper_enable),
    .dir(stepper_direction),
    .step(stepper_step),
    .CYCLE_COUNT(stepper_pwm_cycle),
    .DUTY_COUNT(stepper_pwm_duty),
    .drv_a1(drv_ain1),
    .drv_a2(drv_ain2),
    .drv_b1(drv_bin1),
    .drv_b2(drv_bin2)
);

task step(input dir);
begin
    @(posedge aclk);
    stepper_enable <= 1;
    stepper_direction <= dir;
    stepper_step <= 1'b1;
    @(posedge aclk);
    stepper_step <= 1'b0;
end
endtask

initial begin
    aclk = 0;
    forever #5 aclk = !aclk;
end

initial begin
    areset = 1;
    #100 areset = 0;
    stepper_enable = 0;
    stepper_direction = 0;
    stepper_step = 0;

    stepper_pwm_cycle = 20;
    stepper_pwm_duty = 10;
    #100;
    stepper_enable = 1;

    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;

    stepper_enable <= 0;
    stepper_pwm_duty <= 2;
    #1000;
    stepper_enable <= 0;

    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;

    stepper_enable <= 0;
    stepper_pwm_duty <= 2000;
    #1000;
    stepper_enable <= 0;

    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(0);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;
    step(1);
    #1000;


    #10000;
    stepper_enable <= 1'b0;
    #100;

    $stop;
end



endmodule
