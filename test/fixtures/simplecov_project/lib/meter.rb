class Meter
  def initialize(reading)
    @reading = reading
  end

  def doubled
    @reading * 2
  end

  def label
    "meter"
  end
end
