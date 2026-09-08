using System.Numerics;

namespace TestDataGenerator;

public sealed class Generator
{
    private readonly int _fracBits;

    private readonly uint _controlBase;
    private readonly uint _controlMin;
    private readonly uint _controlMax;

    public double Kp { get; }
    public double Ki { get; }
    public double Kd { get; }

    private readonly long _kpFixed;
    private readonly long _kiFixed;
    private readonly long _kdFixed;

    private BigInteger _integrator;

    private long _previousError;
    private bool _hasPreviousError;

    public Generator(
        double kp,
        double ki,
        double kd,
        int fracBits = 20,
        uint controlBase = 0x8000_0000,
        uint controlMin = 0x0000_0000,
        uint controlMax = 0xFFFF_FFFF)
    {
        Kp = kp; Ki = ki; Kd = kd;

        _fracBits = fracBits;

        _controlBase = controlBase;
        _controlMin = controlMin;
        _controlMax = controlMax;

        _kpFixed = ToFixed(kp);
        _kiFixed = ToFixed(ki);
        _kdFixed = ToFixed(kd);
    }

    public long KpFixed => _kpFixed;
    public long KiFixed => _kiFixed;
    public long KdFixed => _kdFixed;

    public void Reset()
    {
        _integrator = BigInteger.Zero;
        _previousError = 0;
        _hasPreviousError = false;
    }

    public TestResult Calculate(
        uint measured,
        uint target)
    {
        // error = target - measured
        //
        // В Verilog это signed 33 bit.
        long error = (long)target - measured;

        // P = error * Kp
        BigInteger pMult =
            (BigInteger)error * _kpFixed;

        // I[n] = I[n-1] + error * Ki
        BigInteger iMult =
            (BigInteger)error * _kiFixed;

        _integrator += iMult;

        // D = Kd * (error[n] - error[n-1])
        long deltaError;

        if (_hasPreviousError)
        {
            deltaError =
                error - _previousError;
        }
        else
        {
            // На первом измерении D = 0
            deltaError = 0;
        }

        BigInteger dMult =
            (BigInteger)deltaError * _kdFixed;

        // P + I + D.
        //
        // Все значения пока находятся в fixed-point
        // масштабе 2^FracBits.
        BigInteger correctionFixed =
            pMult +
            _integrator +
            dMult;

        // Убираем дробную часть.
        BigInteger correction =
            correctionFixed >> _fracBits;

        // Добавляем поправку к рабочей точке.
        BigInteger control =
            (BigInteger)_controlBase +
            correction;

        // Saturation выхода.
        if (control < _controlMin)
            control = _controlMin;
        else if (control > _controlMax)
            control = _controlMax;

        _previousError = error;
        _hasPreviousError = true;

        return new TestResult(
            measured,
            target,
            (uint)control,
            error);
    }

    public void GenerateFile(
        string fileName,
        uint target,
        int count,
        int initialOffset,
        int randomSeed = 12345)
    {
        Reset();

        var measuredValues = GenerateMeasurements(
            target,
            count,
            initialOffset,
            randomSeed);

        using var writer =
            new StreamWriter(fileName);

        foreach (uint measured in measuredValues)
        {
            TestResult result =
                Calculate(measured, target);

            // measured target expected_control expected_error
            writer.WriteLine(
                $"{result.Measured} " +
                $"{result.Target} " +
                $"{result.Control} " +
                $"{result.Error}");
        }
    }

    public IEnumerable<uint> GenerateMeasurements(
        uint target,
        int count,
        int initialOffset,
        int randomSeed = 12345)
    {
        var random = new Random(randomSeed);

        for (int i = 0; i < count; i++)
        {
            double drift =
                initialOffset *
                Math.Exp(-i / 100.0);

            int noise =
                random.Next(-2, 3);

            long measured =
                (long)target +
                (long)Math.Round(drift) +
                noise;

            measured = Math.Clamp(
                measured,
                (long)uint.MinValue,
                (long)uint.MaxValue);

            yield return (uint)measured;
        }
    }

    private long ToFixed(double value)
    {
        double scale =
            Math.Pow(2.0, _fracBits);

        return checked(
            (long)Math.Round(
                value * scale,
                MidpointRounding.AwayFromZero));
    }

    public readonly record struct TestResult(
        uint Measured,
        uint Target,
        uint Control,
        long Error);
}

