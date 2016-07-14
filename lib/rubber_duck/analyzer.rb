module RubberDuck
  class Analyzer
    attr_reader :database, :asts

    def initialize(database, asts)
      @database = database
      @asts = asts
    end

    def self.load(database_path, script_paths)
      database = Defsdb::Database.open(database_path)
      asts = script_paths.map do |script_path|
        Parser::CurrentRuby.parse(script_path.read, script_path.to_s)
      end

      new(database, asts)
    end

    This = Struct.new(:type, :klass)

    def run
      ControlFlowGraph.new.tap do |graph|
        this = This.new(:instance, database.resolve_constant("Object"))
        asts.each do |ast|
          GraphConstructor.new(database, graph).with_self(this) do |c|
            c.with_module database.resolve_constant("Object") do |c|
              c.push_vertex(ControlFlowGraph::Vertex::Toplevel.instance) do |c|
                c.analyze_expr(ast)
              end
            end
          end
        end
      end
    end

    class GraphConstructor
      attr_reader :database
      attr_reader :graph

      attr_reader :selfs
      attr_reader :vertex_stack
      attr_reader :context

      def initialize(database, graph)
        @database = database
        @graph = graph

        @selfs = []
        @vertex_stack = []
        @context = []
      end

      def with_self(this)
        selfs << this
        yield self
        selfs.pop
      end

      def push_vertex(vertex)
        vertex_stack.push vertex
        yield self
        vertex_stack.pop
      end

      def with_module(mod)
        context << mod if mod
        yield self
        context.pop if mod
      end

      def current_self
        selfs.last
      end

      def current_vertex
        vertex_stack.last
      end

      def current_module
        context.last
      end

      def analyze_expr(expr)
        return unless expr

        case expr.type
        when :send
          receiver = expr.children[0]
          method_name = expr.children[1].to_s
          args = expr.children.drop(2)
          bodys = possible_call_bodys(receiver, method_name, args)

          loc = ControlFlowGraph::Location.from_loc(expr.loc)
          call_vertex = ControlFlowGraph::Vertex::SendNode.new(location: loc, method_name: method_name, node: expr)

          unless bodys.empty?
            graph.add_body_edge(current_vertex, call_vertex)
            bodys.each do |body|
              graph.add_call_edge(call_vertex, ControlFlowGraph::Vertex::MethodBody.new(body: body))
            end
          end

          analyze_children(expr)

        when :block
          send_node = expr.children.first
          receiver = send_node.children[0]
          method_name = send_node.children[1].to_s
          args = send_node.children.drop(2)

          bodys = possible_call_bodys(receiver, method_name, args)

          block_body_node = expr.children[2]

          unless bodys.empty?
            bodys.each do |method_body|
              do_send_vertex = ControlFlowGraph::Vertex::DoSend.new(method_body: method_body, block_body: block_body_node)
              graph.add_body_edge(current_vertex, do_send_vertex)
              push_vertex do_send_vertex do
                analyze_expr(block_body_node)
              end
            end
          end

          args.each do
            analyze_children(args)
          end

        when :def
          name = expr.children[0].to_s
          method = current_module.defined_methods.find {|method|
            method.name == name
          }

          push_vertex ControlFlowGraph::Vertex::MethodBody.new(body: method.body) do
            this = This.new(:instance, current_self.klass)
            with_self this do
              analyze_expr(expr.children.last)
            end
          end

        when :class, :module
          name = expr.children[0]

          if name.type == :const
            mod_name = name.children.last.to_s
            mod = current_module.constants[mod_name]
            with_module mod do
              with_self This.new(:module, mod) do
                analyze_expr expr.children.last
              end
            end
          else
            p "Unknown class #{name}"
          end

        else
          analyze_children(expr)
        end
      end

      def analyze_children(node)
        node.children.each do |child|
          if child.is_a? Parser::AST::Node
            analyze_expr(child)
          end
        end
      end

      def method_bodys(name)
        database.methods.values.select {|method| method.name == name }
      end

      def possible_call_bodys(receiver, method_name, args)
        bodys = method_bodys(method_name).select {|body|
          valid_application?(body.parameters, args)
        }

        if receiver && receiver.type == :const
          const = database.resolve_constant(receiver.children.last.to_s, context.map(&:name))
          if const
            bodys = self.class.possible_fcall_bodys(method_name, bodys, This.new(:module, const))
          end
        end

        bodys
      end

      def self.possible_fcall_bodys(name, bodys, current_self)
        case current_self.type
        when :module
          definition = current_self.klass.defined_singleton_methods.find {|method| method.name == name}
        when :instance
          definition = current_self.klass.defined_instance_methods.find {|method| method.name == name }
        end

        if definition
          [definition.body]
        else
          bodys
        end
      end

      include ApplicationHelper
    end
  end
end