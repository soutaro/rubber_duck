def fact(n, acc = 1)
  if n == 0
    acc
  else
    fact(n-1, acc * n)
  end
end

a = fact(3)
