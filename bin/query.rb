require 'pathname'
require 'bundler/setup'

$LOAD_PATH << (Pathname(__dir__).parent + "lib").to_s

require 'rubber_duck'

require 'optparse'
require 'readline'

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
    "\"block:#{node.block_node.loc.first_line}:#{node.block_node.loc.column}\""
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

puts "Ready:"
puts "  > trace toplevel Array#each String.new"

while true
  line = Readline.readline("> ", true)
  break unless line

  input = line.split
  command = input.first
  args = input.drop(1)

  case command
  when "trace"
    q = args.map {|a|
      if a == "toplevel"
        :toplevel
      else
        a
      end
    }

    traces = graph.select_trace(*q)
    traces.each do |trace|
      trace.each do |t|
        case t
        when RubberDuck::Query::TraceGraph::Node::MethodBody
          loc = t.method_body.location
          puts "#{loc&.first}:#{loc&.last}:#{t.method_body.name}@#{t.method_body.owner.name || "unknown class (maybe singleton class)"}"
        when RubberDuck::Query::TraceGraph::Node::Block
          puts "#{t.block_node.loc.first_line}:[block]"
        when :toplevel
          puts "[toplevel]"
        else
          puts "Unknown trace: #{t.inspect}"
        end
      end
      puts
    end

    puts "Found #{traces.count} possible traces"
  else
    puts "Unknown command: #{command}"
  end


end
