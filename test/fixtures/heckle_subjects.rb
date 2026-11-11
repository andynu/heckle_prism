class HeckleSubjects
  define_method(:defined_dynamically) { 1 }

  def answer
    42
  end

  def pair
    [1, 2]
  end

  def self.class_answer
    42
  end

  class << self
    def singleton_answer
      42
    end
  end

  def explode
    [1].first
    raise ArgumentError, "kaboom"
  end

  def call_hidden
    hidden_answer
  end

  def call_guarded(other)
    other.guarded_answer
  end

  protected def guarded_answer
    42
  end

  # Public, though Kernel#format is private.
  def format
    42
  end

  private

  def hidden_answer
    42
  end
end

class HeckleSubjectsChild < HeckleSubjects
  def own_answer
    42
  end

  def answer
    43
  end

  # Public, though the parent's is protected.
  def guarded_answer
    44
  end
end

# The second answer is never defined: the raise ends the class body.
class HeckleSubjectsHalfLoaded
  def answer
    42
  end
  raise "stop here"

  def answer
    0
  end
rescue RuntimeError
  nil
end

class HeckleSubjectsEvaled
  class_eval("def gone\n  1\nend", "/nonexistent/heckle_gone.rb", 1)
end

module HeckleNesting
  LIMIT = 10

  class Inner
    def limit
      LIMIT + 1
    end

    # String and heredoc content lines indented less than the def.
    def letter(name)
      if name
        heading = "Dear
  #{name},"
      end
      <<-TEXT
#{heading}
  thanks
      TEXT
    end
  end
end

class HeckleSubjectsInit
  attr_reader :value

  def initialize
    @value = 42
  end
end
