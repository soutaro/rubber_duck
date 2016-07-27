module RubberDuck
  module Query
    class TraceGraph
      module Node
        class MethodBody
          attr_reader :method_body
          attr_reader :location

          def initialize(method_body:, location: nil)
            @method_body = method_body
            @location = location
          end

          def ==(other)
            if other.is_a? self.class
              method_body == other.method_body && location == other.location
            end
          end

          def eql?(other)
            self == other
          end

          def hash
            method_body.hash ^ location.hash
          end
        end

        class Block
          attr_reader :block_node

          def initialize(block_node:)
            @block_node = block_node
          end

          def ==(other)
            if other.is_a? self.class
              block_node == other.block_node
            end
          end

          def eql?(other)
            self == other
          end

          def hash
            # seems Parser::AST::Node#hash does not work as expected
            block_node.loc.to_s.hash
          end
        end
      end

      class Edge
        attr_reader :source
        attr_reader :destination

        def initialize(source:, destination:)
          @source = source
          @destination = destination
        end

        def ==(other)
          if other.is_a?(self.class)
            source == other.source && destination == other.destination
          end
        end

        def eql?(other)
          self == other
        end

        def hash
          source.hash ^ destination.hash
        end
      end

      class Sort
        include TSort

        attr_reader :graph
        attr_reader :child_cache
        attr_reader :nodes

        def initialize(graph:)
          @graph = graph

          @nodes = Set.new
          @child_cache = {}

          graph.each_edge do |edge|
            source = edge.source
            child_cache[source] ||= []
            child_cache[source] << edge.destination

            nodes << edge.source
            nodes << edge.destination
          end
        end

        def tsort_each_child(node, &block)
          child_cache[node]&.each(&block)
        end

        def tsort_each_node(&block)
          nodes.each &block
        end
      end

      attr_reader :edges
      attr_reader :nodes
      attr_reader :analyzer
      attr_reader :reachable_nodes

      def initialize(analyzer:)
        @edges = Set.new
        @nodes = Set.new
        @analyzer = analyzer

        construct()
      end

      def each_edge(&block)
        edges.each &block
      end

      def each_node(&block)
        nodes.each &block
      end

      def select_trace(*query)
        raise "Query should have at least two components: #{query.join(", ")}" if query.size < 2

        q = query.map do |component|
          case component
          when String
            Node::MethodBody.new(method_body: analyzer.find_method_body(component))
          when Symbol
            component
          else
            raise "Unknown query component: #{component}"
          end
        end

        calculate_trace(current: q.first, rest: q.drop(1)).map {|t| [q.first] + t }
      end

      private

      def construct
        construct_relations_map

        @relations_map.keys.each do |source|
          case source
          when Defsdb::Database::MethodBody, Symbol
            construct_graph_from(source: source, blocks: [], block_loc: nil)
          end
        end

        calculate_reachability
      end

      def construct_graph_from(source:, blocks: [], block_loc:)
        src_node = case source
                   when Defsdb::Database::MethodBody
                     new_node { Node::MethodBody.new(method_body: source, location: block_loc) }
                   when Parser::AST::Node
                     new_node { Node::Block.new(block_node: source) }
                   when Symbol
                     new_node { source }
                   else
                     raise "Unknown source: #{source.class}"
                   end

        yield_flag = :no_implementation

        visit src_node do
          relations_for(source: source).each do |relation|
            yield_flag = :has_implementation if yield_flag == :no_implementation

            case relation
            when ControlFlowAnalysis::Relation::PassCall
              if relation.pass_through_block
                unless blocks.empty?
                  dest_node = new_node { Node::MethodBody.new(method_body: relation.callee, location: block_loc) }
                  new_edge { Edge.new(source: src_node, destination: dest_node) }

                  construct_graph_from(source: relation.callee, blocks: blocks, block_loc: block_loc)
                end
              end

            when ControlFlowAnalysis::Relation::BlockCall
              dest_node = new_node { Node::MethodBody.new(method_body: relation.callee, location: relation.location) }
              new_edge { Edge.new(source: src_node, destination: dest_node) }

              construct_graph_from(source: relation.callee, blocks: [relation.block_node] + blocks, block_loc: relation.location)

            when ControlFlowAnalysis::Relation::Call
              dest_node = new_node { Node::MethodBody.new(method_body: relation.callee, location: nil) }
              new_edge { Edge.new(source: src_node, destination: dest_node) }

              construct_graph_from(source: relation.callee, blocks: [], block_loc: nil)

            when ControlFlowAnalysis::Relation::Yield
              unless blocks.empty?
                block = blocks.first

                dest_node = new_node { Node::Block.new(block_node: block) }
                new_edge { Edge.new(source: src_node, destination: dest_node) }

                construct_graph_from(source: block, blocks: blocks.drop(1), block_loc: block_loc)

                yield_flag = :yielded
              end
            end
          end
        end

        if src_node.is_a?(Node::MethodBody) && yield_flag == :no_implementation && !blocks.empty?
          dest_node = new_node { Node::Block.new(block_node: blocks.first) }
          new_edge { Edge.new(source: src_node, destination: dest_node) }

          construct_graph_from(source: blocks.first, blocks: blocks.drop(1), block_loc: block_loc)
        end
      end

      def construct_relations_map
        @relations_map = Hash.new { Set.new }

        analyzer.relations.each do |relation|
          source = case relation
                   when ControlFlowAnalysis::Relation::Call
                     relation.caller
                   when ControlFlowAnalysis::Relation::Yield
                     relation.source
                   when ControlFlowAnalysis::Relation::Implementation
                     # nop
                   else
                     raise "Unknown relation: #{relation.inspect}"
                   end

          set = @relations_map[source]
          set << relation
          @relations_map[source] = set
        end
      end

      def relations_for(source:)
        @relations_map[source]
      end

      def calculate_reachability
        @reachable_nodes = {}

        sort = Sort.new(graph: self)

        sort.strongly_connected_components.each do |nodes|
          node_set = Set.new

          sort.each_strongly_connected_component_from(nodes.first) do |component|
            component.each do |node|
              node_set << node
            end
          end

          nodes.each do |node|
            reachable_nodes[node] = node_set
          end
        end
      end

      def reachable_nodes_from(node)
        reachable_nodes[node] || Set.new
      end

      def reachable_method_body?(from:, method_body:)
        reachable_nodes_from(from).any? {|node|
          node.is_a?(Node::MethodBody) && node.method_body == method_body
        }
      end

      def reachable_node?(from:, node:)
        reachable_nodes_from(from).member?(node)
      end

      def calculate_trace(current:, rest:)
        next_node = rest.first

        traces = [].tap do |array|
          each_edge_from(current) do |edge|
            calculate_trace0(from: edge.destination, to: next_node, results: array)
          end
        end

        if traces.empty?
          []
        else
          if rest.size > 1
            traces.flat_map {|prefix|
              calculate_trace(current: prefix.last, rest: rest.drop(1)).map {|suffix|
                prefix + suffix
              }
            }
          else
            traces
          end
        end
      end

      def calculate_trace0(from:, to:, prefix: [], results: [])
        return if prefix.include?(from)

        case
        when from.is_a?(Node::MethodBody) && from.method_body == to.method_body
          results << prefix + [from]
        when reachable_method_body?(from: from, method_body: to.method_body)
          each_edge_from(from) do |edge|
            calculate_trace0(from: edge.destination, to: to, prefix: prefix + [from], results: results)
          end
        end
      end

      def each_edge_from(source)
        edges.each do |edge|
          if edge.source == source
            yield edge
          end
        end
      end

      def visit(node)
        @visited_nodes ||= Set.new

        unless @visited_nodes.member?(node)
          @visited_nodes << node
          yield
        end
      end

      def new_node
        yield.tap do |node|
          nodes << node
        end
      end

      def new_edge
        yield.tap do |edge|
          edges << edge
        end
      end
    end
  end
end
