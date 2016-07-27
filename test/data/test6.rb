def f
  yield if block_given?
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

def test1
  [].each do |_|
    f do |_|
      yield
    end
  end
end

test1 do
  i
end

test1 do
  p 1
end
