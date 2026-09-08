`timescale 1ns/1ps

module pid_controller #(
    parameter integer FRAC_BITS = 20,

    // Номинальное управляющее значение
    parameter [31:0] CONTROL_BASE = 32'h8000_0000,

    // Ограничения управляющего выхода
    parameter [31:0] CONTROL_MIN  = 32'h0000_0000,
    parameter [31:0] CONTROL_MAX  = 32'hFFFF_FFFF,

    // Ограничения интегратора.
    // Интегратор хранится в масштабе Q(FRAC_BITS).
    parameter signed [79:0] I_MIN =
        -80'sh0000_0001_0000_0000_0000,

    parameter signed [79:0] I_MAX =
         80'sh0000_0001_0000_0000_0000
)(
    input  wire clk,
    input  wire rst,

    // Импульс на 1 такт clk, когда measured_count валиден
    input  wire sample_valid,

    // Измеренное количество тактов за фиксированное окно
    input  wire [31:0] measured_count,

    // Ожидаемое количество тактов за это же окно
    input  wire [31:0] target_count,

    // Коэффициенты PID в fixed-point Q(FRAC_BITS).
    // Период дискретизации должен быть учтён в ki и kd.
    //
    // Например при FRAC_BITS = 20:
    // 1.0   = 1048576
    // 0.5   = 524288
    // 0.01  = 10486
    input  wire signed [31:0] kp,
    input  wire signed [31:0] ki,
    input  wire signed [31:0] kd,

    // Итоговый управляющий код
    output reg [31:0] control_out,

    // Для диагностики
    output reg signed [32:0] error_out
);

    // ------------------------------------------------------------
    // Ошибка
    //
    // target и measured unsigned 32 bit.
    // Их разность требует signed 33 bit.
    // ------------------------------------------------------------

    wire signed [32:0] error;

    assign error =
        $signed({1'b0, target_count}) -
        $signed({1'b0, measured_count});


    // ------------------------------------------------------------
    // Изменение ошибки для D-составляющей
    //
    // Разность двух signed 33-bit значений требует 34 bit.
    // На первом отсчёте после rst D-составляющая равна нулю.
    // ------------------------------------------------------------

    reg signed [32:0] error_prev;
    reg               error_prev_valid;

    wire signed [33:0] error_diff;

    assign error_diff =
        error_prev_valid ?
            ($signed({error[32], error}) -
             $signed({error_prev[32], error_prev})) :
            34'sd0;


    // ------------------------------------------------------------
    // Умножения
    //
    // error:      33 bit
    // error_diff: 34 bit
    // kp/ki/kd:   32 bit
    //
    // P/I результат: 65 bit
    // D результат:   66 bit
    // ------------------------------------------------------------

    wire signed [64:0] p_mult;
    wire signed [64:0] i_mult;
    wire signed [65:0] d_mult;

    assign p_mult = error * kp;
    assign i_mult = error * ki;
    assign d_mult = error_diff * kd;


    // ------------------------------------------------------------
    // Интегратор
    //
    // Храним его в масштабе fixed-point.
    // Не делаем >>> FRAC_BITS при каждом накоплении, чтобы
    // не терять малые дробные поправки.
    // ------------------------------------------------------------

    reg signed [79:0] integrator;

    // Начальное значение интегратора — ноль, ограниченный диапазоном I_MIN..I_MAX.
    localparam signed [79:0] I_RESET =
        (80'sd0 < I_MIN) ? I_MIN :
        (80'sd0 > I_MAX) ? I_MAX :
                           80'sd0;

    wire signed [79:0] i_mult_ext;

    assign i_mult_ext =
        {{15{i_mult[64]}}, i_mult};


    wire signed [79:0] integrator_raw;

    assign integrator_raw =
        integrator + i_mult_ext;


    // Saturation интегратора

    wire signed [79:0] integrator_next;

    assign integrator_next =
        (integrator_raw > I_MAX) ? I_MAX :
        (integrator_raw < I_MIN) ? I_MIN :
                                   integrator_raw;


    // ------------------------------------------------------------
    // P-составляющая
    // ------------------------------------------------------------

    wire signed [79:0] p_mult_ext;

    assign p_mult_ext =
        {{15{p_mult[64]}}, p_mult};


    // ------------------------------------------------------------
    // D-составляющая
    // ------------------------------------------------------------

    wire signed [79:0] d_mult_ext;

    assign d_mult_ext =
        {{14{d_mult[65]}}, d_mult};


    // ------------------------------------------------------------
    // Полная поправка.
    //
    // P, I и D находятся в Q(FRAC_BITS).
    // Поэтому сначала складываем их в одном масштабе,
    // затем один раз сдвигаем.
    // ------------------------------------------------------------

    wire signed [80:0] correction_fixed;

    assign correction_fixed =
        $signed({p_mult_ext[79], p_mult_ext}) +
        $signed({integrator_next[79], integrator_next}) +
        $signed({d_mult_ext[79], d_mult_ext});


    wire signed [80:0] correction;

    assign correction =
        correction_fixed >>> FRAC_BITS;


    // ------------------------------------------------------------
    // CONTROL_BASE + signed correction
    //
    // Используем дополнительный бит, чтобы нормально определить
    // выход за диапазон 0..2^32-1.
    // ------------------------------------------------------------

    wire signed [81:0] control_base_ext;
    wire signed [81:0] correction_ext;
    wire signed [81:0] control_raw;

    assign control_base_ext =
        $signed({1'b0, 49'd0, CONTROL_BASE});

    assign correction_ext =
        {{1{correction[80]}}, correction};

    assign control_raw =
        control_base_ext + correction_ext;


    // Границы также переводим в широкий signed формат

    wire signed [81:0] control_min_ext;
    wire signed [81:0] control_max_ext;

    // Начальное значение выхода также должно находиться в заданном диапазоне.
    localparam [31:0] CONTROL_RESET =
        (CONTROL_BASE < CONTROL_MIN) ? CONTROL_MIN :
        (CONTROL_BASE > CONTROL_MAX) ? CONTROL_MAX :
                                       CONTROL_BASE;

    assign control_min_ext =
        $signed({1'b0, 49'd0, CONTROL_MIN});

    assign control_max_ext =
        $signed({1'b0, 49'd0, CONTROL_MAX});


    // ------------------------------------------------------------
    // Регистры
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            integrator <= I_RESET;
            error_prev <= 33'sd0;
            error_prev_valid <= 1'b0;
            control_out <= CONTROL_RESET;
            error_out <= 33'sd0;
        end
        else if (sample_valid) begin
            integrator <= integrator_next;
            error_prev <= error;
            error_prev_valid <= 1'b1;
            error_out <= error;

            if (control_raw < control_min_ext)
                control_out <= CONTROL_MIN;
            else if (control_raw > control_max_ext)
                control_out <= CONTROL_MAX;
            else
                control_out <= control_raw[31:0];
        end
    end

endmodule
