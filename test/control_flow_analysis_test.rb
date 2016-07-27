require_relative 'test_helper'

describe RubberDuck::ControlFlowAnalysis do
  include TestHelper

  it "does something" do
    database = database("test1.rb")

    analyzer = RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
      analyzer.add_source_code data_script_path("test1.rb")
    end

    assert has_call_relation?(analyzer, from: :toplevel, to: "Object#fact")
    assert has_call_relation?(analyzer, from: "Object#fact", to: "Object#fact")
  end

  it "does something test3.rb" do
    database = database("test3.rb")

    analyzer = RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
      analyzer.add_source_code data_script_path("test3.rb")
    end

    assert has_call_relation?(analyzer, from: "Object#entry1", to: "Module1.f")
    assert has_call_relation?(analyzer, from: "Object#entry2", to: "Module2.f")

    refute has_call_relation?(analyzer, from: "Object#entry1", to: "Module2.f")
    refute has_call_relation?(analyzer, from: "Object#entry2", to: "Module1.f")
  end

  it "analyze test4.rb" do
    database = database("test4.rb")

    analyzer = RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
      analyzer.add_source_code data_script_path("test4.rb")
    end

    assert has_call_relation?(analyzer, from: "Object#entry1", to: "String#f")
    assert has_call_relation?(analyzer, from: "Object#entry2", to: "Integer#f")

    refute has_call_relation?(analyzer, from: "Object#entry1", to: "Integer#f")
    refute has_call_relation?(analyzer, from: "Object#entry2", to: "String#f")
  end

  describe "analyzing test5.rb" do
    it "has extra precision on constant method call" do
      database = database("test5.rb")

      analyzer = RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
        analyzer.add_source_code data_script_path("test5.rb")
      end

      assert has_call_relation?(analyzer, from: "A#g", to: "String#f")
      refute has_call_relation?(analyzer, from: "A#g", to: "Array#f")
      assert has_call_relation?(analyzer, from: "A::B#g", to: "Array#f")
      refute has_call_relation?(analyzer, from: "A::B#g", to: "String#f")
    end

    it "does not have extra precision on non constant call" do
      database = database("test5.rb")
      analyzer = RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
        analyzer.add_source_code data_script_path("test5.rb")
      end

      assert has_call_relation?(analyzer, from: "Object#entry", to: "A#g")
      assert has_call_relation?(analyzer, from: "Object#entry", to: "A::B#g")
    end
  end

  Block = Struct.new(:line)

  describe "analyzing test6.rb" do
    it "handles block" do
      database = database("test6.rb")

      analyzer = RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
        analyzer.add_source_code data_script_path("test6.rb")
      end

      assert has_block_call_relation?(analyzer, from: :toplevel, to: "Object#f")

      refute has_call_relation?(analyzer, from: :toplevel, to: "Object#g")
      assert has_call_relation?(analyzer, from: Block.new(8), to: "Object#g")

      assert has_yield_relation?(analyzer, source: "Object#f")

      assert has_call_relation?(analyzer, from: "Object#h", to: "Object#f", blockarg: true, pass_through: true)
      assert has_call_relation?(analyzer, from: "Object#i", to: "Object#f", blockarg: true, pass_through: false)
    end
  end

  def has_call_relation?(analyzer, from:, to:, blockarg: false, pass_through: nil)
    caller = case from
             when String
               find_method_body(analyzer, from)
             else
               from
             end

    callee = case to
             when String
               find_method_body(analyzer, to)
             else
               to
             end

    analyzer.relations.select {|rel|
      if !blockarg
        rel.is_a?(RubberDuck::ControlFlowAnalysis::Relation::Call)
      else
        rel.is_a?(RubberDuck::ControlFlowAnalysis::Relation::PassCall) && (pass_through == nil || rel.pass_through_block == pass_through)
      end
    }.any? {|rel|
      caller_test = if caller.is_a?(Block)
                      rel.caller.is_a?(Parser::AST::Node) && rel.caller.type == :block && rel.caller.loc.first_line == caller.line
                    else
                      rel.caller == caller
                    end
      caller_test && rel.callee == callee
    }
  end

  def has_block_call_relation?(analyzer, from:, to:)
    caller = case from
             when String
               find_method_body(analyzer, from)
             else
               from
             end

    callee = case to
             when String
               find_method_body(analyzer, to)
             else
               to
             end

    analyzer.relations.any? {|rel| rel.is_a?(RubberDuck::ControlFlowAnalysis::Relation::BlockCall) && rel.caller == caller && rel.callee == callee }
  end

  def has_yield_relation?(analyzer, source:)
    source = case source
           when String
             find_method_body(analyzer, source)
           else
             source
           end

    analyzer.relations.any? {|rel| rel.is_a?(RubberDuck::ControlFlowAnalysis::Relation::Yield) && rel.source == source }
  end

  def find_method_body(analyzer, method)
    case method
    when /\./
      klass_name, method_name = method.split(/\./)
      analyzer.database.find_method_definition(klass_name, singleton_method: method_name).body
    when /#/
      klass_name, method_name = method.split(/#/)
      analyzer.database.find_method_definition(klass_name, instance_method: method_name).body
    end
  end
end
