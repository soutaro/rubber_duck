module Module1
  def test1(a, b)
  end
end

module Module2
  def test1()
  end
end

def entry1
  # resolves to Module2#test1
  test1()
end

def entry2
  # resolves to Module1#test1
  test1(1, 2)
end

def entry3
  # does not resolve to neither Module1#test1 nor Module2#test1
  test1(1)
end

def entry4
  # resolves to Module1#test1 and Module2#test2
  test1(*[])
end
