class Thermometer
  def self.freezing
    new(0)
  end

  def initialize celsius
    @celsius = celsius
  end

  def fahrenheit
    @celsius * 9 / 5 + 32
  end
end
