require "thermometer_test"

def thermometer_readings
  [Thermometer.new(100).fahrenheit, Thermometer.freezing.fahrenheit]
rescue StandardError => e
  e.class
end

# Under -v the tests write to heckle's stdout. Once a mutant is installed
# this test says so and blocks until the reader closes stdin, which it does
# after closing stdout, so the next write fails while the mutant is still
# in place. Minitest's progress dots may precede the marker on its line.
class ThermometerPipeTest < Minitest::Test
  def test_announce_mutant
    return if thermometer_readings == [212, 32]

    puts "mutant installed"
    $stdin.read
  end
end

# Reports, as the process ends, whether the original methods are back.
at_exit { $stderr.puts "at exit: #{thermometer_readings.inspect}" }
