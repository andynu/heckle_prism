# Holds one chunk per row. With -n call, the first of load's mutants
# replaces @rows.size with nil, so the range is endless and load holds a
# megabyte more every five milliseconds or so until something stops it.
class Hoarder
  CHUNK = 1024 * 1024

  def initialize(rows)
    @rows = rows
  end

  def load
    held = []
    (1..@rows.size).each { held << chunk }
    held.join.size
  end

  def chunk
    sleep 0.005
    "x" * CHUNK
  end
end
