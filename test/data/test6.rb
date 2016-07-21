def f
  yield
end

def g
end

f do
  g
end

def h(&block)
  f &block
end

def i()
  block = proc {}
  f &block
end

h do
  g
end

f
