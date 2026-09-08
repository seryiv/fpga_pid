using System.Numerics;

namespace TestDataGenerator;

public class Generator
{
    private const int FracBits = 20;

    private const uint ControlBase = 0x0000_03E8;
    private const uint ControlMin = 0x0000_0000;
    private const uint ControlMax = 0xFFFF_FFFF;

    // Реальные коэффициенты.
    // Ниже они будут преобразованы в fixed-point.
    public double Kp { get; init; } //0.25
    public double Ki { get; init; } //0.001

    private readonly long _kpFixed;
    private readonly long _kiFixed;

    // Аналог 80-битного integrator из Verilog.
    // BigInteger позволяет не думать о переполнении C#.
    private static BigInteger _integrator;

    public Generator(double kp, double ki)
    {
        Kp = kp;
        Ki = ki;
        _kpFixed = ToFixed(Kp);
        _kiFixed = ToFixed(Ki);
    }

    private static long ToFixed(double value)
    {
        double scale = 1L << FracBits;

        return checked(
            (long)Math.Round(
                value * scale,
                MidpointRounding.AwayFromZero));
    }

    public TestResult Calculate(uint measured, uint target)
    {
        // В Verilog:
        //
        // error =
        //   $signed({1'b0, target_count}) -
        //   $signed({1'b0, measured_count});
        //
        // Диапазон помещается в Int64.
        long error = (long)target - measured;

        // error: 33 bit
        // coefficient: signed 32 bit
        //
        // В Verilog произведение имеет fixed-point масштаб 2^FracBits.
        BigInteger pMult = (BigInteger)error * _kpFixed;
        BigInteger iMult = (BigInteger)error * _kiFixed;

        // Интегратор хранится ДО удаления дробных битов.
        _integrator += iMult;

        // При необходимости сюда можно добавить те же I_MIN/I_MAX,
        // что используются в Verilog.
        //
        // _integrator = Clamp(_integrator, iMin, iMax);

        BigInteger correctionFixed =
            pMult + _integrator;

        // Аналог арифметического >>> FRAC_BITS.
        //
        // BigInteger >> для отрицательных чисел выполняет
        // арифметический сдвиг.
        BigInteger correction =
            correctionFixed >> FracBits;

        BigInteger control =
            (BigInteger)ControlBase + correction;

        if (control < ControlMin)
            control = ControlMin;
        else if (control > ControlMax)
            control = ControlMax;

        return new TestResult(
            measured,
            target,
            (uint)control,
            error);
    }

    public IEnumerable<uint> GenerateMeasurements(
        uint target,
        int count,
        int initialOffset)
    {
        var random = new Random(12345);

        for (int i = 0; i < count; i++)
        {
            // Имитируем постепенно изменяющуюся ошибку генератора.
            //
            // В начале генератор примерно на initialOffset тактов
            // быстрее требуемого значения.
            double drift =
                initialOffset *
                Math.Exp(-i / 100.0);

            // Квантование/шум измерения примерно +/- 2 такта.
            int noise = random.Next(-2, 3);

            long measured =
                (long)target +
                (long)Math.Round(drift) +
                noise;

            measured = Math.Clamp(
                measured,
                uint.MinValue,
                uint.MaxValue);

            yield return (uint)measured;
        }
    }
    public readonly record struct TestResult(
        uint Measured,
        uint Target,
        uint Control,
        long Error);

}