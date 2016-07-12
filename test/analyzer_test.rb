require_relative 'test_helper'

describe RubberDuck::Analyzer do
  include TestHelper

  Vertex = RubberDuck::ControlFlowGraph::Vertex

  it "analyzes test1.rb" do
    analyzer = analyzer("test1.rb")
    graph = analyzer.run

    fact = analyzer.database.find_method_definition("Object", instance_method: "fact")

    # contains edge from Object#fact => Object#fact
    assert has_method_call?(graph, from: fact.body, to: fact.body)

    # contains edge from :toplevel => Object#fact
    assert has_method_call?(graph, from: Vertex::Toplevel.instance, to: fact.body)
  end

  describe "test2.rb" do
    it "contains edge from entry1 => Module2#test1" do
      analyzer = analyzer("test2.rb")
      graph = analyzer.run

      entry1 = analyzer.database.find_method_definition("Object", instance_method: "entry1")
      entry2 = analyzer.database.find_method_definition("Object", instance_method: "entry2")
      test1 = analyzer.database.find_method_definition("Module2", instance_method: "test1")

      assert has_method_call?(graph, from: entry1.body, to: test1.body)
      refute has_method_call?(graph, from: entry2.body, to: test1.body)
    end

    it "contains edge from entry2 => Module1#test1" do
      analyzer = analyzer("test2.rb")
      graph = analyzer.run

      entry1 = analyzer.database.find_method_definition("Object", instance_method: "entry1")
      entry2 = analyzer.database.find_method_definition("Object", instance_method: "entry2")
      test1 = analyzer.database.find_method_definition("Module1", instance_method: "test1")

      assert has_method_call?(graph, from: entry2.body, to: test1.body)
      refute has_method_call?(graph, from: entry1.body, to: test1.body)
    end

    it "does not contain edge from entry3 => test1" do
      analyzer = analyzer("test2.rb")
      graph = analyzer.run

      entry3 = analyzer.database.find_method_definition("Object", instance_method: "entry3")
      refute has_method_call?(graph, from: entry3.body, to: nil)
    end

    it "contains edges from entry3 => Module1#test1 and Module2#test1" do
      analyzer = analyzer("test2.rb")
      graph = analyzer.run

      entry4 = analyzer.database.find_method_definition("Object", instance_method: "entry4")
      test1_1 = analyzer.database.find_method_definition("Module1", instance_method: "test1")
      test1_2 = analyzer.database.find_method_definition("Module2", instance_method: "test1")

      assert has_method_call?(graph, from: entry4.body, to: test1_1.body)
      assert has_method_call?(graph, from: entry4.body, to: test1_2.body)
    end
  end

  describe "test3.rb" do
    it "resolves constant's methods with extra precision" do
      analyzer = analyzer("test3.rb")
      graph = analyzer.run

      entry1 = analyzer.database.find_method_definition("Object", instance_method: "entry1").body
      entry2 = analyzer.database.find_method_definition("Object", instance_method: "entry2").body
      f1 = analyzer.database.find_method_definition("Module1", singleton_method: "f").body
      f2 = analyzer.database.find_method_definition("Module2", singleton_method: "f").body

      assert has_method_call?(graph, from: entry1, to: f1)
      refute has_method_call?(graph, from: entry1, to: f2)

      assert has_method_call?(graph, from: entry2, to: f2)
      refute has_method_call?(graph, from: entry2, to: f1)
    end
  end

  describe "test4.rb" do
    it "resolves constant's methods with extra precision" do
      analyzer = analyzer("test4.rb")
      graph = analyzer.run

      entry1 = analyzer.database.find_method_definition("Object", instance_method: "entry1").body
      entry2 = analyzer.database.find_method_definition("Object", instance_method: "entry2").body
      string_f = analyzer.database.find_method_definition("String", instance_method: "f").body
      integer_f = analyzer.database.find_method_definition("Integer", instance_method: "f").body

      assert has_method_call?(graph, from: entry1, to:string_f)
      refute has_method_call?(graph, from: entry1, to: integer_f)

      assert has_method_call?(graph, from: entry2, to: integer_f)
      refute has_method_call?(graph, from: entry2, to: string_f)
    end
  end

  # If there is a method call from method body to method body
  def has_method_call?(graph, from:, to:)
    from_node = from.is_a?(Vertex::Base) ? from : Vertex::MethodBody.new(body: from)
    to_node = to ? Vertex::MethodBody.new(body: to) : to

    call_nodes = graph.edges.map {|edge|
      if edge.from == from_node
        edge.to
      end
    }.compact.to_set

    graph.edges.any? {|edge|
      call_nodes.member?(edge.from) && (to == nil || edge.to == to_node)
    }
  end
end
