module HeckleBlocks
  SCALE = 10

  Point = Data.define(:x, :y) do
    def sum
      x + y + 1
    end

    def self.origin_sum
      42
    end
  end

  Pair = Struct.new(:a, :b) do
    def scaled
      a * SCALE + 1
    end

    class << self
      def answer
        42
      end
    end

    private def hidden
      42
    end

    def call_hidden
      hidden
    end
  end

  class Base
    def base_answer
      42
    end
  end

  Child = Class.new(Base) do
    def answer
      42
    end

    def scaled
      SCALE + 1
    end
  end

  # Not visible to the methods of the block: their lexical scope is the
  # module, and the module's SCALE is found first.
  Child.const_set(:SCALE, 99)

  Mixin = Module.new do
    def mixed
      42
    end
  end
end
