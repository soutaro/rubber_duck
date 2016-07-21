module RubberDuck
  module Query
    module Trace
      class Base
        attr_reader :sub_query

        def initialize(sub_query:)
          @sub_query = sub_query
        end
      end

      class Call < Base
        attr_reader :name

        def initialize(name:, sub_query:)
          super(sub_query: sub_query)
          @name = name
        end

        def append(query)
          if sub_query
            Call.new(name: name, sub_query: sub_query.append(query))
          else
            Call.new(name: name, sub_query: query)
          end
        end
      end

      class Root < Base
        def append(query)
          if sub_query
            Root.new(sub_query: sub_query.append(query))
          else
            Root.new(sub_query: query)
          end
        end

        def call(name)
          append(Call.new(name: name, sub_query: nil))
        end
      end

      class Selector
        attr_reader :analyzer

        def initialize(analyzer:)
          @analyzer = analyzer
        end

        def run(start:, query:)
          select(current: start, query: query.sub_query, prefix: [], results: [], block: nil)
        end

        private

        def select(current:, query:, prefix:, results:, block: nil)
          if prefix.include?(current)
            results
          else
            next_prefix = prefix + [current]

            n = find_method_body(query.name)

            return results unless n

            if block && include_block_application?(current)
              select(current: block, query: query, prefix: next_prefix, results: results)
            end

            edges = calls_from(current)

            edges.each do |edge|
              next_node = edge.callee

              b = case edge
                  when ControlFlowAnalysis::Relation::PassCall
                    edge.pass_through_block ? block : nil
                  when ControlFlowAnalysis::Relation::BlockCall
                    edge.block_node
                  end

              if next_node == n
                if query.sub_query
                  select(current: edge.callee, query: query.sub_query, prefix: [], results: [], block: b).each do |result|
                    results << (next_prefix + result)
                  end
                else
                  results << (next_prefix + [n])
                end
              else
                select(current: edge.callee, query: query, prefix: next_prefix, results: results, block: b)
              end
            end

            results
          end
        end

        def calls_from(current, type: Object)
          analyzer.relations.select {|rel|
            case rel
            when ControlFlowAnalysis::Relation::Call
              rel.caller == current
            end
          }.select {|rel| rel.is_a? type }.to_set
        end

        def include_block_application?(current)
          includes_yield = analyzer.relations.any? {|rel|
            case rel
            when ControlFlowAnalysis::Relation::Yield
              rel.source == current
            end
          }
          includes_pass = analyzer.relations.any? {|rel|
            case rel
            when ControlFlowAnalysis::Relation::PassCall
              rel.caller == current && rel.pass_through_block
            when ControlFlowAnalysis::Relation::BlockCall
              rel.caller == current && include_block_application?(rel.block_node)
            end
          }

          includes_yield || !includes_pass
        end

        def find_method_body(name)
          case name
          when /\./
            klass_name, method_name = name.split(/\./)
            klass = analyzer.database.resolve_constant(klass_name)
            klass.defined_singleton_methods.find {|method| method.name == method_name }&.body
          when /#/
            klass_name, method_name = name.split(/#/)
            klass = analyzer.database.resolve_constant(klass_name)
            klass.defined_instance_methods.find {|method| method.name == method_name }&.body
          else
            raise "Unknown method name: #{name}"
          end
        end
      end

      def self.root
        Root.new(sub_query: nil)
      end

      def self.select(analysis, start:, query:)
        Selector.new(analyzer: analysis).run(start: start, query: query)
      end
    end
  end
end
