class Squarer
  def square(n)
    if n.is_a?(Numeric)
      n ** 2
    else
      "not a number"
    end
  end
end
