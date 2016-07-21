module RubberDuck
  module ControlFlowAnalysis
    Location = Struct.new(:file, :start_line, :start_column, :end_line, :end_column) do
      def self.from_node(file:, node:)
        new(file, node.loc.first_line, node.loc.column, node.loc.last_line, node.loc.last_column)
      end

      def ==(other)
        other.is_a?(self.class) &&
          file == other.file &&
          start_line == other.start_line &&
          start_column == other.start_column &&
          end_line == other.end_line &&
          end_column == other.end_column
      end

      def eql?(other)
        self == other
      end

      def hash
        file.hash ^ start_line ^ start_column ^ end_line ^ end_column
      end
    end

    module Relation
      class Base
      end

      class Call < Base
        # MethodBody, :toplevel, or Node (block)
        attr_reader :caller

        # Location of send node
        attr_reader :location

        # MethodBody
        attr_reader :callee

        def initialize(caller:, location:, callee:)
          @caller = caller
          @location = location
          @callee = callee
        end
      end

      class BlockCall < Call
        # :block node
        attr_reader :block_node

        def initialize(caller:, location:, callee:, block_node:)
          super(caller: caller, location: location, callee: callee)
          @block_node = block_node
        end
      end

      class PassCall < Call
        # true when passed block arg is given to method
        attr_reader :pass_through_block

        def initialize(caller:, location:, callee:, pass_through_block:)
          super(caller: caller, location: location, callee: callee)
          @pass_through_block = pass_through_block
        end
      end

      class Yield < Base
        attr_reader :source
        attr_reader :location

        def initialize(source:, location:)
          @source = source
          @location = location
        end
      end
    end

    class Analyzer
      attr_reader :database
      attr_reader :relations
      attr_reader :sources

      def initialize(database:)
        @database = database
        @relations = []
        @sources = {}
      end

      def add_source_code(file)
        @sources[file.realpath] = Parser::CurrentRuby.parse(file.read)
      end

      def self.run(database: )
        analyzer = new(database: database)
        yield analyzer

        processor = Processor.new(analyzer: analyzer)
        analyzer.sources.each do |file, node|
          processor.run(file: file, node: node)
        end

        analyzer
      end

      class Processor
        include ApplicationHelper

        attr_reader :analyzer
        attr_reader :file
        attr_reader :module_stack
        attr_reader :caller_stack
        attr_reader :self_stack
        attr_reader :blockarg_stack

        def initialize(analyzer:)
          @analyzer = analyzer
          @file = nil
          @module_stack = []
          @caller_stack = []
          @self_stack = []
          @blockarg_stack = []
        end

        def with_file(file)
          @file = file
          yield
          @file = nil
        end

        def push_caller(caller)
          @caller_stack.push caller
          yield
          @caller_stack.pop
        end

        def current_caller
          @caller_stack.last
        end

        def push_module(name, mod)
          @module_stack.push [name, mod]
          yield
          @module_stack.pop
        end

        def current_module
          @module_stack.last.last
        end

        def push_blockarg(blockarg)
          blockarg_stack.push blockarg
          yield
          blockarg_stack.pop
        end

        def current_blockarg
          blockarg_stack.last
        end

        def run(file:, node:)
          object_class = analyzer.database.resolve_constant("Object")

          with_file file do
            push_module "Object", object_class do
              push_caller :toplevel do
                analyze_node(node)
              end
            end
          end
        end

        def analyze_node(node)
          return unless node

          case node.type
          when :send
            bodies = method_body_candidates(node)

            args = node.children.drop(2)
            pass_arg = args.find {|arg| arg.type == :block_pass }&.children&.first

            bodies.each do |body|
              loc = Location.from_node(file: file, node: node)
              if pass_arg
                pass_through = pass_arg.type == :lvar && pass_arg.children.last == current_blockarg
                call = Relation::PassCall.new(caller: current_caller, location: loc, callee: body, pass_through_block: pass_through)
              else
                call = Relation::Call.new(caller: current_caller, location: loc, callee: body)
              end

              add_relation call
            end

            analyze_children node

          when :block
            bodies = method_body_candidates(node.children.first)

            loc = Location.from_node(file: file, node: node)
            bodies.each do |body|
              block_call = Relation::BlockCall.new(caller: current_caller, location: loc, callee: body, block_node: node)
              add_relation block_call
            end

            analyze_children node.children[0]
            analyze_node node.children[1]

            push_caller node do
              node.children.drop(2).each do |child|
                analyze_node child
              end
            end

          when :yield
            loc = Location.from_node(file: file, node: node)
            add_relation Relation::Yield.new(source: current_caller, location: loc)

            analyze_children node

          when :def
            body = method_body_from_database(node)
            if body
              args = node.children[1]
              blockarg = args.children.find {|arg| arg.type == :blockarg }&.children&.first

              push_caller body do
                push_blockarg blockarg do
                  analyze_children node
                end
              end
            else
              puts "Unknown method definition in database found; skipping... #{file}:#{node.loc.first_line}"
            end

          when :class, :module
            name = node.children.first

            if name.type == :const
              const_name = name.children.last.to_s
              mod = resolve_constant(name.children.last.to_s)
              push_module const_name, mod do
                analyze_children node
              end
            else
              p "Module is not constant: #{name}"
            end

          else
            analyze_children node
          end
        end

        def analyze_children(node)
          node.children.each do |child|
            if child.is_a?(Parser::AST::Node)
              analyze_node child
            end
          end
        end

        def method_body_from_database(node)
          analyzer.database.each_method_body.find {|body|
            body.name == node.children[0].to_s && body.location && Pathname(body.location.first).realpath.to_s == file.to_s && body.location.last == node.loc.first_line
          }
        end

        def resolve_constant(name)
          analyzer.database.resolve_constant(name, module_stack.map(&:first))
        end

        def method_body_candidates(node)
          receiver = node.children.first
          name = node.children[1].to_s
          args = node.children.drop(2)

          case
          when receiver && receiver.type == :const
            constant = resolve_constant(receiver.children.last.to_s)
            Array(constant.defined_singleton_methods.find {|method|
              method.name == name && valid_application?(method.body.parameters, args)
            }.body)
          else
            analyzer.database.each_method_body.select {|body|
              body.name == name && valid_application?(body.parameters, args)
            }
          end
        end

        def add_relation(relation)
          analyzer.relations << relation
        end
      end
    end
  end
end
