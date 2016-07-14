require 'rubber_duck'
require 'optparse'
# require 'dir'

database = Pathname("defs_database.json")
output_path = Pathname("a.dot")
prefixes = []
layout = "dot"

OptionParser.new do |opts|
  opts.on("--database=DATABASE") {|path| database = Pathname(path) }
  opts.on("-o OUTPUT") {|path| output_path = Pathname(path) }
  opts.on("--prefix PREFIX") {|path| prefixes << Pathname(path) }
  opts.on("--layout layout") {|l| layout = l }
end.parse!(ARGV)

def format_vertex(vertex)
  case vertex
  when RubberDuck::ControlFlowGraph::Vertex::Toplevel
    "Toplevel"
  when RubberDuck::ControlFlowGraph::Vertex::MethodBody
    "\"#{vertex.body.name}@#{vertex.body.owner.name || vertex.body.owner.id}\""
  when RubberDuck::ControlFlowGraph::Vertex::SendNode
    "\"#{vertex.method_name}:#{vertex.location.start_line}:#{vertex.location.start_column}\""
  when RubberDuck::ControlFlowGraph::Vertex::DoSend
    "\"#{vertex.method_body.name}@#{vertex.method_body.owner.name || vertex.method_body.owner.id}:#{vertex.block_body.loc.first_line}:#{vertex.block_body.loc.column}\""
  end
end

def format_vertex_option(vertex)
  case vertex
  when RubberDuck::ControlFlowGraph::Vertex::Toplevel
    "[shape = doublecircle]"
  when RubberDuck::ControlFlowGraph::Vertex::MethodBody
    ""
  when RubberDuck::ControlFlowGraph::Vertex::SendNode
    "[shape = box]"
  when RubberDuck::ControlFlowGraph::Vertex::DoSend
    "[shape = box]"
  end
end

analyzer = RubberDuck::Analyzer.load(database, ARGV.map {|path| Pathname(path) })
cfg = analyzer.run

output_path.open('w') do |io|
  io.puts "digraph RubberDuck {"

  io.puts <<EOD
graph [
  charset = "UTF-8";
  layout = #{layout};
];
EOD

  destinations = Set.new
  sources = Set.new

  cfg.edges.each do |edge|
    sources << edge.from
    destinations << edge.to
  end

  vs = Set.new
  vs += sources
  destinations.each do |dest|
    if prefixes.size > 0 && dest.is_a?(RubberDuck::ControlFlowGraph::Vertex::MethodBody)
      if dest.body.location && prefixes.any? {|prefix| dest.body.location.first =~ /#{prefix.realpath.to_s}/ }
        vs << dest
      end
    else
      vs << dest
    end

  end

  vs.each do |body|
    io.puts "#{format_vertex(body)} #{format_vertex_option(body)};"
  end

  cfg.edges.each do |edge|
    if vs.member? edge.to
      io.puts "#{format_vertex(edge.from)} -> #{format_vertex(edge.to)};"
    end
  end

  io.puts "}"
end
