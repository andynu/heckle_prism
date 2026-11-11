# With -n call, tally has two mutants: the note dropped from @notes
# survives, since no test reads the notes, and @entries.size replaced by
# nil makes the range endless, so the loop spins until the timeout.
# first's one mutant is killed, and initialize has none.
class Ledger
  def initialize(entries)
    @entries = entries
    @notes = []
  end

  def first
    @entries.first
  end

  def tally
    @notes << :tallied
    rows = 0
    (1..@entries.size).each { rows += 1 }
    rows
  end
end
