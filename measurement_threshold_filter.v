`timescale 1ns/1ps

module measurement_threshold_filter #(
    parameter integer WIDTH = 32,
    parameter [WIDTH-1:0] MAX_DELTA = 32'd100
)(
    input  wire                 clk,
    input  wire                 rst,

    input  wire                 sample_valid,
    input  wire [WIDTH-1:0]     sample_in,

    output reg                  filtered_valid,
    output reg  [WIDTH-1:0]     filtered_out,
    output reg                  sample_rejected
);

    reg [WIDTH-1:0] last_accepted;
    reg             has_accepted_sample;

    wire [WIDTH-1:0] delta;

    // Модуль разности без знакового переполнения.
    assign delta =
        (sample_in >= last_accepted) ? (sample_in - last_accepted) :
                                       (last_accepted - sample_in);

    always @(posedge clk) begin
        if (rst) begin
            last_accepted       <= {WIDTH{1'b0}};
            has_accepted_sample <= 1'b0;
            filtered_valid      <= 1'b0;
            filtered_out        <= {WIDTH{1'b0}};
            sample_rejected     <= 1'b0;
        end
        else begin
            // Оба сигнала являются импульсами длительностью один такт.
            filtered_valid  <= 1'b0;
            sample_rejected <= 1'b0;

            if (sample_valid) begin
                // Первый отсчёт задаёт начальную точку сравнения.
                if (!has_accepted_sample || (delta <= MAX_DELTA)) begin
                    last_accepted       <= sample_in;
                    has_accepted_sample <= 1'b1;
                    filtered_out        <= sample_in;
                    filtered_valid      <= 1'b1;
                end
                else begin
                    // Выброс не меняет последнее принятое значение.
                    sample_rejected <= 1'b1;
                end
            end
        end
    end

endmodule
