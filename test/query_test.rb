require_relative "test_helper"

describe RubberDuck::Query do
  include TestHelper

  def analyzer(name)
    database = database(name)
    RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
      analyzer.add_source_code data_script_path(name)
    end
  end

  it "does something" do
    analyzer = analyzer("test5.rb")

    query1 = RubberDuck::Query::Trace.root.call("A::B#g").call("Array#f")
    query2 = RubberDuck::Query::Trace.root.call("A::B#g").call("String#f")

    refute_empty RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: query1)
    assert_empty RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: query2)
  end

  it "does something2" do
    analyzer = analyzer("test5.rb")
    graph = RubberDuck::Query::TraceGraph.new(analyzer: analyzer)

    refute_empty graph.select_trace(:toplevel, "A::B#g")
    refute_empty graph.select_trace(:toplevel, "A::B#g", "Array#f")
    assert_empty graph.select_trace(:toplevel, "A::B#g", "String#f")
  end

  it "analyze recursive call" do
    analyzer = analyzer("test1.rb")
    graph = RubberDuck::Query::TraceGraph.new(analyzer: analyzer)

    refute_empty graph.select_trace(:toplevel, "Object#fact")
    refute_empty graph.select_trace(:toplevel, "Object#fact", "Object#fact")
  end

  it "analyzes block call" do
    analyzer = analyzer("test6.rb")
    graph = RubberDuck::Query::TraceGraph.new(analyzer: analyzer)

    refute_empty graph.select_trace(:toplevel, "Object#f", "Object#g")
    refute_empty graph.select_trace(:toplevel, "Object#h", "Object#g")
  end

  it "analyzes block call2" do
    analyzer = analyzer("test6.rb")
    graph = RubberDuck::Query::TraceGraph.new(analyzer: analyzer)

    t1 = graph.select_trace(:toplevel, "Object#f", "Object#g")
    t2 = graph.select_trace(:toplevel, "Object#h", "Object#g")
    t3 = graph.select_trace(:toplevel, "Object#g")

    assert_empty(t3 - t1)
    refute_empty(t3 - t2)
  end
end
