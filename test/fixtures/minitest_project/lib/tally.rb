class Tally
  attr_reader :count

  def self.start
    new
  end

  def initialize
    @count = 0
  end

  def bump
    step = 1
    @count += step
    self
  end

  def label
  end
end
