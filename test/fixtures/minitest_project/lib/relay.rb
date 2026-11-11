# With -n call, pass_on has three mutants, in this order: @entries.size
# replaced by nil makes the range endless, so the loop spins until the
# timeout; the note dropped from @notes survives, since no test reads the
# notes; and @entries.first replaced by nil is killed.
class Relay
  def initialize(entries)
    @entries = entries
    @notes = []
  end

  def pass_on
    rows = 0
    (1..@entries.size).each { rows += 1 }
    @notes << rows
    @entries.first
  end

  # The same with the surviving note first: with -n call the note
  # survives, the endless range times out and @entries.first comes last.
  def hand_over
    @notes << :handed
    rows = 0
    (1..@entries.size).each { rows += 1 }
    @entries.first
  end

  # The same shape holding a megabyte per row: with -n call its first
  # mutant holds a megabyte more every five milliseconds or so until
  # something stops it, the next four survive and the last is killed.
  def gather
    held = []
    (1..@entries.size).each { held << chunk }
    @notes << held.size
    @entries.first
  end

  def chunk
    sleep 0.005
    "x" * (1024 * 1024)
  end
end
