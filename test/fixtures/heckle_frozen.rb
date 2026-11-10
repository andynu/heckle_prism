# frozen_string_literal: true

class HeckleFrozen
  def literal_frozen
    [1, "abc".frozen?]
  end

  def explode
    [1].first
    raise ArgumentError, "kaboom"
  end
end
