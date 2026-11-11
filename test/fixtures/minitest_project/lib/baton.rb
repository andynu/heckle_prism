# With -n call: first's one mutant is killed, initialize has none, pass's
# first mutant makes the range endless and its second is killed, and
# peek's one mutant is killed.
class Baton
  def initialize(entries)
    @entries = entries
  end

  def first
    @entries.first
  end

  def pass
    rows = 0
    (1..@entries.size).each { rows += 1 }
    @entries.last
  end

  def peek
    @entries.last
  end
end
