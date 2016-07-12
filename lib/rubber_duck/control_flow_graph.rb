module RubberDuck
  class ControlFlowGraph
    attr_reader :edges

    def initialize()
      @edges = Set.new
    end

    module Vertex
      # Singleton
      class Toplevel
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

      class MethodBody
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

    class Edge
      attr_reader :from, :to, :kind

      def initialize(from, to, kind)
        raise "Unexpected kind #{kind}" unless %i(name).include?(kind)

        @from = from
        @to = to
        @kind = kind
      end

      def eql?(other)
        if other.is_a? Edge
          from == other.from && to == other.to && kind == other.kind
        end
      end

      def hash
        from.hash ^ to.hash ^ kind.hash
      end
    end

    def add_edge(from, to, kind)
      edges << Edge.new(from, to, kind)
    end

    def has_edge?(from: nil, to: nil)
      edges.any? {|edge|
        (from == nil || edge.from == from) && (to == nil || edge.to == to)
      }
    end
  end
end
