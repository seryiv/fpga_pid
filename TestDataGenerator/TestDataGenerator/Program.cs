
using System.Globalization;
using TestDataGenerator;

var ci = CultureInfo.CreateSpecificCulture("EN-us");
ci.NumberFormat.NumberDecimalSeparator = ".";

var generator = new Generator(0.25,0.001);

var target = 20_000u;

var values = generator.GenerateMeasurements(target, 10, 21);

using var writer = new StreamWriter(args[0]);

writer.WriteLine("kp ki");
writer.WriteLine($"{generator.Kp.ToString(ci)} {generator.Ki.ToString(ci)}");
writer.WriteLine("measured target expected_control expected_error");

foreach (uint measured in values)
{
    var result = generator.Calculate(measured, target);

    writer.WriteLine(
        $"{measured} " +
        $"{target} " +
        $"{result.Control} " +
        $"{result.Error}");
}