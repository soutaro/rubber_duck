module RubberDuck
  class ControlFlowGraph
    attr_reader :edges

    def initialize()
      @edges = Set.new
    end

    Location = Struct.new(:start_line, :start_column, :end_line, :end_column) do
      def self.from_loc(loc)
        new(loc.first_line, loc.column, loc.last_line, loc.last_column)
      end
    end

    module Vertex
      class Base
      end

      # Singleton
      class Toplevel < Base
        def ==(other)
          other.is_a? self.class
        end

        def hash
          self.class.hash
        end

        def self.instance
          @instance ||= self.new
        end
      end

      class SendNode < Base
        # Location
        attr_reader :location

        attr_reader :method_name

        # Optional
        attr_reader :node

        def initialize(location:, method_name:, node:)
          @location = location
          @method_name = method_name
          @node = node
        end

        def ==(other)
          if other.is_a?(SendNode)
            location == other.location && method_name == other.method_name
          end
        end

        def eql?(other)
          self == other
        end

        def hash
          location.hash ^ method_name.hash
        end
      end

      class MethodBody < Base
        attr_reader :body

        def initialize(body:)
          @body = body
        end

        def ==(other)
          other.is_a?(MethodBody) && body == other.body
        end

        def eql?(other)
          self == other
        end

        def hash
          body.hash
        end
      end
    end

    module Edge
      class Base
        attr_reader :from, :to

        def initialize(from:, to:)
          @from = from
          @to = to
        end

        def eql?(other)
          if other.class == self.class
            from == other.from && to == other.to
          end
        end

        def hash
          from.hash ^ to.hash
        end
      end

      # Node in included in method definition
      # From MethodBody to SendNode
      class MethodBody < Base
      end

      # Method call
      # from SendNode to MethodBody
      class Call < Base
      end
    end

    def add_call_edge(from, to)
      edges << Edge::Call.new(from: from, to: to)
    end

    def add_body_edge(from, to)
      edges << Edge::MethodBody.new(from: from, to: to)
    end

    def has_edge?(from: nil, to: nil)
      edges.any? {|edge|
        (from == nil || edge.from == from) && (to == nil || edge.to == to)
      }
    end
  end
end
