# Application code that rescues broadly around a loop. With -n call,
# count_rows has two mutants: @sheet.first replaced by nil raises a
# TypeError at once, and @sheet.last replaced by nil makes the range
# endless, so the loop spins forever without allocating.
class Importer
  def initialize(sheet)
    @sheet = sheet
  end

  def count_rows
    rows = 0
    (@sheet.first..@sheet.last).each { rows += 1 }
    rows
  end

  def import
    count_rows
  rescue StandardError
    -1
  end

  def import_stubbornly
    count_rows
  rescue Exception
    -1
  end

  def import_retrying
    count_rows
  rescue Exception
    retry
  end
end
