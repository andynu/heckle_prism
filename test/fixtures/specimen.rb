# Mutation targets for the mutator, method finder and heckler tests. Most
# methods hold one kind of mutation site. Tests pin exact mutants and line
# numbers, so an edit here moves expectations in test_mutator.rb,
# test_method_finder.rb and test_heckle_prism.rb.
class Specimen
  attr_accessor :labels

  def initialize
    @labels = []
  end

  def booleans
    sealed = true
    sealed && false
  end

  def numbers
    count = 3
    count += 4294967296
    count -= 0.25
  end

  def one_literal
    9
  end

  def repeated_literal
    dose = 7
    dose += 7
    dose * 7
  end

  def strings
    @labels << "agar plate"
    @labels << "blood smear"
    @labels << "core sample"
  end

  def symbols
    [:thawed, :thawed, :frozen]
  end

  def regexes
    [/[ACGT]+/, /\d{2,3}/, /smear/]
  end

  def ranges
    [2..40, -3..8, 0..7]
  end

  def branch_if
    if ready?
      if labelled?
        :stored
      end
    else
      :waiting
    end
  end

  def branch_unless
    unless labelled?
      if ready?
        relabel
      end
    end
  end

  def loop_while
    while ready?
      relabel
    end
  end

  def loop_until
    until labelled?
      relabel
    end
  end

  def calls
    weight * volume
  end

  def call_with_block
    tray.map { 2 }
  end

  def iterates
    doses = [4, 5, 6]
    doses.map { |dose| dose }
  end

  def local_assignments
    tally = 12
    tally = nil
    tally
  end

  def instance_assignments
    @reading = 0.5
    @reading = nil
  end

  def global_assignments
    $batch = "B7"
    $batch = nil
  end

  def class_variable_assignments
    @@stock = :low
    @@stock = nil
  end

  def block_assignment
    tray.each do |slot|
      count = slot
      count = nil
      count
    end
  end

  def multiple_assignment
    @low, $mid, high = 1, 2, 3
    high
  end

  def assay
    passes = 0
    until passes == 3
      passes += 1
      while labelled?
        relabel
      end
      return :rejected if grade == "C"
    end
    weight > 2.5 || false
  end

  def inert
  end

  def self.sterile?
    false
  end

  module Freezer
    def position
      :freezer
    end

    module Shelf
      def position
        :upper_shelf
      end

      class Box
        def capacity
          81
        end
      end
    end

    module Shelf
      def position
        :lower_shelf
      end

      class Box
        module Lookalike
          def position
            :lookalike
          end
        end

        def position
          :box
        end
      end
    end
  end

  private

  def ready?; end
  def labelled?; end
  def relabel; end
  def grade; end
  def weight; end
  def volume; end
  def tray; end
end
