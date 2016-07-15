class String
  def f
    puts "String#f"
  end
end

class Array
  def f
    puts "Array#f"
  end
end

class Integer
  def f
    puts "Integer#f"
  end
end

module A
  X = ""

  def g
    X.f
  end

  module B
    X = []

    def g
      X.f
    end
  end
end
#
# X = 3
#
# module A::C
#   def h
#     X.f
#   end
# end
