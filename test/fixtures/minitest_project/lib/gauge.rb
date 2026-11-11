require_relative "../../outside_helper"

class Gauge
  extend OutsideHelper

  calibrate_with 42
  attr_accessor :level

  def read
    level
  end
end
