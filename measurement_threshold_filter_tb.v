`timescale 1ns/1ps

module measurement_threshold_filter_tb;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         sample_valid = 1'b0;
    reg  [31:0] sample_in = 32'd0;

    wire        filtered_valid;
    wire [31:0] filtered_out;
    wire        sample_rejected;

    measurement_threshold_filter #(
        .WIDTH    (32),
        .MAX_DELTA(32'd10)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .sample_valid   (sample_valid),
        .sample_in      (sample_in),
        .filtered_valid (filtered_valid),
        .filtered_out   (filtered_out),
        .sample_rejected(sample_rejected)
    );

    always #5 clk = ~clk;

    task send_and_check;
        input [31:0] value;
        input        expected_valid;
        input        expected_rejected;
        input [31:0] expected_value;
        begin
            @(negedge clk);
            sample_in    = value;
            sample_valid = 1'b1;

            @(posedge clk);
            #1;

            if (filtered_valid !== expected_valid)
                $error("value=%0d: filtered_valid=%b, expected=%b",
                       value, filtered_valid, expected_valid);

            if (sample_rejected !== expected_rejected)
                $error("value=%0d: rejected=%b, expected=%b",
                       value, sample_rejected, expected_rejected);

            if (filtered_out !== expected_value)
                $error("value=%0d: filtered_out=%0d, expected=%0d",
                       value, filtered_out, expected_value);

            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        send_and_check(32'd100, 1'b1, 1'b0, 32'd100); // первый отсчёт
        send_and_check(32'd110, 1'b1, 1'b0, 32'd110); // ровно MAX_DELTA
        send_and_check(32'd200, 1'b0, 1'b1, 32'd110); // выброс
        send_and_check(32'd105, 1'b1, 1'b0, 32'd105); // возврат в диапазон

        $display("measurement_threshold_filter tests passed");
        $finish;
    end

endmodule
