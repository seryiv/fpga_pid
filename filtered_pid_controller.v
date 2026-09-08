`timescale 1ns/1ps

module filtered_pid_controller #(
    parameter integer FRAC_BITS = 20,

    parameter [31:0] FILTER_MAX_DELTA = 32'd100,

    parameter [31:0] CONTROL_BASE = 32'h8000_0000,
    parameter [31:0] CONTROL_MIN  = 32'h0000_0000,
    parameter [31:0] CONTROL_MAX  = 32'hFFFF_FFFF,

    parameter signed [79:0] I_MIN =
        -80'sh0000_0001_0000_0000_0000,

    parameter signed [79:0] I_MAX =
         80'sh0000_0001_0000_0000_0000
)(
    input  wire               clk,
    input  wire               rst,

    // Неотфильтрованное измерение от счётчика.
    input  wire               sample_valid,
    input  wire        [31:0] measured_count,

    input  wire        [31:0] target_count,
    input  wire signed [31:0] kp,
    input  wire signed [31:0] ki,
    input  wire signed [31:0] kd,

    output wire        [31:0] control_out,
    output wire signed [32:0] error_out,

    // Диагностические сигналы фильтра.
    output wire               filtered_valid,
    output wire        [31:0] filtered_count,
    output wire               sample_rejected
);

    measurement_threshold_filter #(
        .WIDTH    (32),
        .MAX_DELTA(FILTER_MAX_DELTA)
    ) measurement_filter (
        .clk            (clk),
        .rst            (rst),
        .sample_valid   (sample_valid),
        .sample_in      (measured_count),
        .filtered_valid (filtered_valid),
        .filtered_out   (filtered_count),
        .sample_rejected(sample_rejected)
    );

    pid_controller #(
        .FRAC_BITS  (FRAC_BITS),
        .CONTROL_BASE(CONTROL_BASE),
        .CONTROL_MIN (CONTROL_MIN),
        .CONTROL_MAX (CONTROL_MAX),
        .I_MIN       (I_MIN),
        .I_MAX       (I_MAX)
    ) controller (
        .clk           (clk),
        .rst           (rst),
        .sample_valid  (filtered_valid),
        .measured_count(filtered_count),
        .target_count  (target_count),
        .kp            (kp),
        .ki            (ki),
        .kd            (kd),
        .control_out   (control_out),
        .error_out     (error_out)
    );

endmodule
