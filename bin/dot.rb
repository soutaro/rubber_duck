require 'pathname'
require 'bundler/setup'

$LOAD_PATH << (Pathname(__dir__).parent + "lib").to_s

require 'rubber_duck'

require 'optparse'

def format_node(node)
  case node
  when RubberDuck::Query::TraceGraph::Node::MethodBody
    owner = node.method_body.owner.name || node.method_body.owner.id
    if node.location
      "\"#{node.method_body.name}@#{owner}:#{node.location.start_line}\""
    else
      "\"#{node.method_body.name}@#{owner}\""
    end
  when RubberDuck::Query::TraceGraph::Node::Block
    "\"block:#{node.block_node.loc.first_line}:#{node.block_node.loc.column}@#{node.location&.start_line}:#{node.location&.end_line}\""
  when Symbol
    "#{node}"
  end
end

def format_node_option(node)
  case node
  when RubberDuck::Query::TraceGraph::Node::MethodBody
    "[shape = box]"
  when RubberDuck::Query::TraceGraph::Node::Block
    "[shape = doublecircle]"
  when Symbol
    "[shape = circle]"
  end
end

DotPath = Pathname("a.dot")

db_path = nil
paths = []

ARGV.each do |file|
  path = Pathname(file)

  case path.extname
  when '.json'
    db_path = path.realpath
  when '.rb'
    paths << path.realpath
  else
    raise "Unknown path extension: #{path}"
  end
end

raise "Specify database path" unless db_path

puts "Loading database..."
database = Defsdb::Database.open(db_path)
puts "ok!"

puts "Running analyzer..."
analyzer = RubberDuck::ControlFlowAnalysis::Analyzer.run(database: database) do |analyzer|
  paths.each do |path|
    analyzer.add_source_code path
  end
end
puts "ok!"

puts "Constructing trace graph..."
graph = RubberDuck::Query::TraceGraph.new(analyzer: analyzer)
puts "ok!"

puts "Writing .dot..."
DotPath.open('w') do |io|
  io.puts "digraph hello {"

  graph.each_node.each do |node|
    io.puts "#{format_node(node)} #{format_node_option(node)};"
  end

  graph.each_edge.each do |edge|
    io.puts "#{format_node(edge.source)} -> #{format_node(edge.destination)};"
  end

  io.puts "}"
end
puts "ok!"
puts "#{graph.edges.count} edges, #{graph.nodes.count} nodes"
