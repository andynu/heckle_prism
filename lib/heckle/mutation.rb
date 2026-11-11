require "prism"

class Heckle
  # One source edit: replace the byte range start_offset...end_offset of the
  # file source with replacement. Offsets are bytes, end exclusive.
  # A frozen Struct taking positional or keyword arguments, which is what
  # Data.define gives on Ruby 3.2 and later.
  Mutation = Struct.new(:kind, :start_offset, :end_offset, :replacement) do
    def initialize(*values, **fields)
      if values.empty?
        values = members.map do |name|
          fields.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end
      end
      super(*values)
      freeze
    end

    # base_offset is the file offset at which source begins, so a mutation
    # with file offsets can be applied to a slice such as one def's text.
    def apply(source, base_offset = 0)
      start = start_offset - base_offset
      source.byteslice(0, start) + replacement + source.byteslice((end_offset - base_offset)..-1)
    end
  end
end
