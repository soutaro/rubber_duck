class String
  def f
  end
end

class Integer
  def f
  end
end

A = ""
B = 3

def entry1
  # resolves to String#f
  A.f
end

def entry2
  # resolves to Integer#f
  B.f
end
