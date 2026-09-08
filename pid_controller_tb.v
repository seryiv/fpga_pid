`timescale 1ns/1ps

module pid_controller_tb (
);

    localparam integer FRAC_BITS = 20;
    localparam signed [31:0] Q_ONE = 32'sd1 <<< FRAC_BITS;
    localparam signed [31:0] Q_HALF = Q_ONE >>> 1;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_valid = 1'b0;

    reg [31:0] measured_count = 32'd0;
    reg [31:0] target_count   = 32'd0;

    reg signed [31:0] kp = 32'sd0;
    reg signed [31:0] ki = 32'sd0;    
    reg signed [31:0] kd = 32'sd0;

    wire [31:0] control_out;
    wire signed [32:0] error_out;

    pid_controller #(
        .FRAC_BITS   (FRAC_BITS),
        .CONTROL_BASE(32'd1000),
        .CONTROL_MIN (32'd0),
        .CONTROL_MAX (32'd2000)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .sample_valid  (sample_valid),
        .measured_count(measured_count),
        .target_count  (target_count),
        .kp            (kp),
        .ki            (ki),
        .kd            (kd),
        .control_out   (control_out),
        .error_out     (error_out)
    );

    always #5 clk = ~clk;

    // Перевод вещественного коэффициента в signed Q(FRAC_BITS)
    // с округлением к ближайшему целому.
    function signed [31:0] real_to_fixed;
        input real value;
        real scaled_value;
        begin
            scaled_value = value * (2.0 ** FRAC_BITS);

            if (scaled_value >= 0.0)
                real_to_fixed = $rtoi(scaled_value + 0.5);
            else
                real_to_fixed = $rtoi(scaled_value - 0.5);
        end
    endfunction

    // Передача одного измерения.
    task send_sample;
        input [31:0] measured;
        input [31:0] target;
        begin
            // Меняем входы на спадающем фронте,
            // чтобы они были стабильны к следующему posedge.
            @(negedge clk);
            measured_count = measured;
            target_count   = target;
            sample_valid   = 1'b1;

            // На этом фронте DUT принимает измерение.
            @(posedge clk);
            #1;

            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask


    task reset_dut;
        begin
            @(negedge clk);
            rst = 1'b1;
            sample_valid = 1'b0;

            repeat (2) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;
        end
    endtask


    task automatic run_test_file;
        input [8*256-1:0] file_name;

        integer file_handle;
        integer scan_result;
        integer read_result;
        integer test_number;

        reg [8*256-1:0] header_line;
        reg [8*256-1:0] coefficients_line;

        reg [31:0] file_measured;
        reg [31:0] file_target;
        reg [31:0] expected_control;
        reg signed [32:0] expected_error;

        real kp_real;
        real ki_real;
        real kd_real;

        begin
            $display("Running test file: %0s", file_name);

            file_handle = $fopen(file_name, "r");

            if (file_handle == 0)
                $fatal(1, "Cannot open file: %0s", file_name);

            // Первая строка содержит заголовок коэффициентов: kp ki kd.
            read_result = $fgets(header_line, file_handle);

            if (read_result == 0)
                $fatal(1, "Test file is empty: %0s", file_name);

            // Вторая строка содержит вещественные значения kp, ki и kd.
            read_result = $fgets(coefficients_line, file_handle);

            if (read_result == 0)
                $fatal(1, "Coefficient values are missing: %0s", file_name);

            scan_result = $sscanf(
                coefficients_line,
                "%f %f %f",
                kp_real,
                ki_real,
                kd_real
            );

            if (scan_result != 3)
                $fatal(1, "Cannot read kp, ki and kd from: %0s", file_name);

            kp = real_to_fixed(kp_real);
            ki = real_to_fixed(ki_real);
            kd = real_to_fixed(kd_real);

            $display(
                "Coefficients: kp=%f (%0d Q), ki=%f (%0d Q), kd=%f (%0d Q)",
                kp_real,
                kp,
                ki_real,
                ki,
                kd_real,
                kd
            );

            // Третья строка содержит заголовок таблицы тестовых данных.
            read_result = $fgets(header_line, file_handle);

            if (read_result == 0)
                $fatal(1, "Test data header is missing: %0s", file_name);

            test_number = 0;

            scan_result = $fscanf(
                file_handle,
                "%d %d %d %d",
                file_measured,
                file_target,
                expected_control,
                expected_error
            );

            while (scan_result == 4) begin
                $display(
                    "Test %0d: measured=%0d target=%0d",
                    test_number,
                    file_measured,
                    file_target
                );

                send_sample(file_measured, file_target);

                if (control_out !== expected_control) begin
                    $error(
                        "Test %0d: control=%0d, expected=%0d",
                        test_number,
                        control_out,
                        expected_control
                    );
                end

                if (error_out !== expected_error) begin
                    $error(
                        "Test %0d: error=%0d, expected=%0d",
                        test_number,
                        error_out,
                        expected_error
                    );
                end

                if ((control_out === expected_control) &&
                    (error_out === expected_error)) begin
                    $display("Test %0d passed", test_number);
                end

                test_number = test_number + 1;

                scan_result = $fscanf(
                    file_handle,
                    "%d %d %d %d",
                    file_measured,
                    file_target,
                    expected_control,
                    expected_error
                );
            end

            $fclose(file_handle);

            $display(
                "Completed %0d tests from %0s",
                test_number,
                file_name
            );
        end
    endtask

    initial begin
        $dumpfile("pid_controller.vcd");
        $dumpvars(0, pid_controller_tb);

        reset_dut();
        run_test_file("test_data/pid_test_data1.csv");

        reset_dut();
        run_test_file("test_data/pid_test_data2.csv");

        reset_dut();
        run_test_file("test_data/pid_test_data3.csv");

        $display("All tests completed");
        $finish;
    end


endmodule
