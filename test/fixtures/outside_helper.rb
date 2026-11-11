# Outside minitest_project, so methods it defines there come from a file
# outside that project, as a gem's generated methods do.
module OutsideHelper
  def calibrate_with(value)
    define_method(:calibrated) { value }
  end
end
