using System.Globalization;
using TestDataGenerator;

var ci = CultureInfo.CreateSpecificCulture("EN-us");
ci.NumberFormat.NumberDecimalSeparator = ".";

var generator = new Generator(0.25, 0.001, 0.1);

var target = 20_000u;

var values = generator.GenerateMeasurements(target, 10, 21);

var fileName = "../../../../../test_data/" + args[0];
if (File.Exists(fileName))
    throw new Exception("File already exists");

using var writer = new StreamWriter(fileName);

writer.WriteLine("kp ki kd");
writer.WriteLine($"{generator.Kp.ToString(ci)} {generator.Ki.ToString(ci)} {generator.Kd.ToString(ci)}");
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