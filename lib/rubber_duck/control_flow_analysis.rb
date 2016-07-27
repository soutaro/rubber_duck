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

      class Implementation < Base
        attr_reader :method_body

        def initialize(method_body:)
          @method_body = method_body
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

      def find_method_body(name)
        case name
        when /\./
          klass_name, method_name = name.split(/\./)
          database.find_method_definition(klass_name, singleton_method: method_name)&.body
        when /#/
          klass_name, method_name = name.split(/#/)
          database.find_method_definition(klass_name, instance_method: method_name)&.body
        else
          raise "Unknown method name: #{name}"
        end
      end

      class Processor
        include ApplicationHelper

        attr_reader :analyzer
        attr_reader :file
        attr_reader :module_context_stack
        attr_reader :module_stack
        attr_reader :caller_stack
        attr_reader :blockarg_stack

        def initialize(analyzer:)
          @analyzer = analyzer
          @file = nil
          @module_context_stack = []
          @module_stack = []
          @caller_stack = []
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

        def push_module_context(mod)
          @module_context_stack.push mod
          yield
          @module_context_stack.pop
        end

        def push_module(mod)
          @module_stack.push mod
          yield
          @module_stack.pop
        end

        def current_module
          @module_stack.last || analyzer.database.object_class
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
          with_file file do
            push_caller :toplevel do
              analyze_node(node)
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

              add_relation Relation::Implementation.new(method_body: body)
            else
              puts "Unknown method definition in database found; skipping... #{file}:#{node.loc.first_line}"
            end

          when :class, :module
            name = node.children.first

            mod = find_constant(name)

            if name.children.first
              push_module mod do
                analyze_children node
              end
            else
              push_module_context mod do
                push_module mod do
                  analyze_children node
                end
              end
            end

          else
            analyze_children node
          end
        end

        def find_constant(const_node)
          path = []
          node = const_node
          while node
            case node.type
            when :const
              path.unshift node.children.last.to_s
              node = node.children.first
            when :cbase
              path.unshift :root
            else
              raise "Unsupported node: #{const_node}"
            end
          end

          analyzer.database.lookup_constant_path(path, current_module: current_module, module_context: module_context_stack)
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
            nameok = body.name == node.children[0].to_s

            path = body.location && Pathname(body.location.first)
            fileok = path&.file? && path.realpath.to_s == file.to_s && body.location.last == node.loc.first_line

            nameok && fileok
          }
        end

        def method_body_candidates(node)
          receiver = node.children.first
          name = node.children[1].to_s
          args = node.children.drop(2)

          case
          when receiver && is_constant?(receiver)
            constant = find_constant(receiver)
            Array(constant.defined_singleton_methods.find {|method|
              method.name == name && valid_application?(method.body.parameters, args)
            }&.body)
          else
            analyzer.database.each_method_body.select {|body|
              body.name == name && valid_application?(body.parameters, args)
            }
          end
        end

        def is_constant?(node)
          case node.type
          when :const
            node.children[0] ? is_constant?(node.children[0]) : true
          when :cbase
            true
          else
            false
          end
        end

        def add_relation(relation)
          analyzer.relations << relation
        end
      end
    end
  end
end
