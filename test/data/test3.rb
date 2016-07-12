module Module1
  def self.f()
  end
end

module Module2
  def self.f()
  end
end

def entry1
  # resolves to Module1.f
  Module1.f
end

def entry2
  # resolves to Module2.f
  Module2.f
end

