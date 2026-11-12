require "prism"

class Heckle
  # One source edit: replace the byte range start_offset...end_offset of the
  # file source with replacement. Offsets are bytes, end exclusive.
  Mutation = Data.define(:kind, :start_offset, :end_offset, :replacement) do
    # base_offset is the file offset at which source begins, so a mutation
    # with file offsets can be applied to a slice such as one def's text.
    def apply(source, base_offset = 0)
      start = start_offset - base_offset
      source.dup.bytesplice(start, end_offset - start_offset, replacement)
    end
  end
end
