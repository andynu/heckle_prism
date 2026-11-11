Money = Struct.new(:cents, keyword_init: true) do
  def dollars
    cents / 100
  end

  def self.zero
    new(cents: 0)
  end
end
