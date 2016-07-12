def fib(n)
  if n == 0
    1
  else
    n * fib(n-1)
  end
end

p fib(10)
