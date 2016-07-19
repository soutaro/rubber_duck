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

  it "analyze recursive call" do
    analyzer = analyzer("test1.rb")

    q1 = RubberDuck::Query::Trace.root.call("Object#fact")
    q2 = q1.call("Object#fact")

    refute_empty RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: q1)
    refute_empty RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: q2)
  end

  it "analyzes block call" do
    analyzer = analyzer("test6.rb")

    q1 = RubberDuck::Query::Trace.root.call("Object#f").call("Object#g")
    q2 = RubberDuck::Query::Trace.root.call("Object#h").call("Object#g")

    refute_empty RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: q1)
    refute_empty RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: q2)

    assert_empty RubberDuck::Query::Trace.select(analyzer,
                                                 start: :toplevel,
                                                 query: RubberDuck::Query::Trace.root.call("Object#f").call("Object#h"))
  end

  it "analyzes block call2" do
    analyzer = analyzer("test6.rb")

    q1 = RubberDuck::Query::Trace.root.call("Object#f").call("Object#g")
    q2 = RubberDuck::Query::Trace.root.call("Object#h").call("Object#g")
    q3 = RubberDuck::Query::Trace.root.call("Object#g")

    t1 = RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: q1)
    t2 = RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: q2)
    t3 = RubberDuck::Query::Trace.select(analyzer, start: :toplevel, query: q3)

    assert_empty(t3 - t1)
    refute_empty(t3 - t2)

    p t3-t2
  end
end
