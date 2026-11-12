Money = Data.define(:cents) do
  def dollars
    cents / 100
  end

  def self.zero
    new(cents: 0)
  end
end
