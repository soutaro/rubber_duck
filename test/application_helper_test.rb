require_relative 'test_helper'

describe RubberDuck::ApplicationHelper do
  include RubberDuck::ApplicationHelper

  describe "valid_application?" do
    it "accepts required params" do
      assert valid_application?([[:req, :x]], args("f(1)"))
      assert valid_application?([[:req, :x], [:req, :y]], args("f(*[])"))
      refute valid_application?([[:req, :x]], args("f()"))
      refute valid_application?([[:req, :x]], args("f(1, 2)"))
    end

    it "accepts optional params" do
      assert valid_application?([[:opt, :x]], args("f()"))
      assert valid_application?([[:opt, :x]], args("f(1)"))
      refute valid_application?([[:opt, :x]], args("f(1, 2)"))
    end

    it "accepts splat args" do
      assert valid_application?([[:req, :x]], args("f(*args)"))
      refute valid_application?([[:req, :x]], args("f(1,2,*args)"))
    end

    it "handles rest args" do
      assert valid_application?([[:rest]], args("f(1,2,3)"))
      assert valid_application?([[:req, :x], [:rest]], args("f(1,2,3)"))
      refute valid_application?([[:req, :x], [:rest]], args("f()"))
    end

    it "accepts keyword args" do
      assert valid_application?([[:keyreq, :x]], args("f(x: 1)"))
      refute valid_application?([[:keyreq, :x]], args("f()"))
      refute valid_application?([[:keyreq, :x]], args("f(a: 1, x: 2)"))
    end

    it "accepts optional keyword args" do
      assert valid_application?([[:key, :x]], args("f(x: 1)"))
      assert valid_application?([[:key, :x]], args("f()"))
      refute valid_application?([[:key, :x]], args("f(a: 1, x: 2)"))
    end

    it "accepts complicated one" do
      assert valid_application?([[:req, :a], [:req, :b], [:opt, :c], [:rest, :d], [:keyreq, :e], [:key, :f], [:keyrest, :g]], args("f(1, 2, e: 1)"))
      assert valid_application?([[:req, :a], [:req, :b], [:opt, :c], [:rest, :d], [:keyreq, :e], [:key, :f], [:keyrest, :g]], args("f(1, 2, 3, 4, e: 5, f: 6, g: 7)"))
      assert valid_application?([[:req, :a], [:req, :b], [:opt, :c], [:rest, :d], [:keyreq, :e], [:key, :f], [:keyrest, :g]], args("f(1, 2, **k)"))
      refute valid_application?([[:req, :a], [:req, :b], [:opt, :c], [:rest, :d], [:keyreq, :e], [:key, :f], [:keyrest, :g]], args("f()"))
      refute valid_application?([[:req, :a], [:req, :b], [:opt, :c], [:rest, :d], [:keyreq, :e], [:key, :f], [:keyrest, :g]], args("f(1, 2)"))
      refute valid_application?([[:req, :a], [:req, :b], [:opt, :c], [:rest, :d], [:keyreq, :e], [:key, :f], [:keyrest, :g]], args("f(1, 2, f: 3)"))
    end

    it "accepts block pass arg" do
      assert valid_application?([[:block, :b]], args("f(&block)"))
      assert valid_application?([], args("f(&block)"))
      assert valid_application?([[:req, :x]], args("f(1, &block)"))
    end
  end

  def args(script)
    Parser::CurrentRuby.parse(script).children.drop(2)
  end
end
