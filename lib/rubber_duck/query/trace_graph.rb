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

      attr_reader :edges
      attr_reader :nodes
      attr_reader :analyzer

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

      private

      def construct
        construct_relations_map

        @relations_map.keys.each do |source|
          case source
          when Defsdb::Database::MethodBody, Symbol
            construct_graph_from(source: source, block: nil, block_loc: nil)
          end
        end
      end

      def construct_graph_from(source:, block:, block_loc:)
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
                dest_node = new_node { Node::MethodBody.new(method_body: relation.callee, location: block_loc) }
                new_edge { Edge.new(source: src_node, destination: dest_node) }

                construct_graph_from(source: relation.callee, block: block, block_loc: block_loc)
              end
            when ControlFlowAnalysis::Relation::BlockCall
              dest_node = new_node { Node::MethodBody.new(method_body: relation.callee, location: relation.location) }
              new_edge { Edge.new(source: src_node, destination: dest_node) }

              construct_graph_from(source: relation.callee, block: relation.block_node, block_loc: relation.location)
            when ControlFlowAnalysis::Relation::Call
              dest_node = new_node { Node::MethodBody.new(method_body: relation.callee, location: nil) }
              new_edge { Edge.new(source: src_node, destination: dest_node) }

              construct_graph_from(source: relation.callee, block: block, block_loc: block_loc)
            when ControlFlowAnalysis::Relation::Yield
              if block
                dest_node = new_node { Node::Block.new(block_node: block) }
                new_edge { Edge.new(source: src_node, destination: dest_node) }

                construct_graph_from(source: block, block: nil, block_loc: nil)

                yield_flag = :yielded
              end
            end
          end
        end

        if yield_flag == :no_implementation && block
          dest_node = new_node { Node::Block.new(block_node: block) }
          new_edge { Edge.new(source: src_node, destination: dest_node) }

          construct_graph_from(source: block, block: nil, block_loc: nil)
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
