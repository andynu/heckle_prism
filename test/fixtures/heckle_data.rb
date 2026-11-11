# Data needs Ruby 3.2, so this file is loaded only where it exists.
module HeckleBlocks
  Point = Data.define(:x, :y) do
    def sum
      x + y + 1
    end

    def self.origin_sum
      42
    end
  end
end
