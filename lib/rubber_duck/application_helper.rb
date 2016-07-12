module RubberDuck
  module ApplicationHelper
    module_function

    def valid_application?(parameters, args)
      args = args.dup

      params = parameters.group_by {|param| param[0] }

      Array(params[:req]).each do |_|
        # require parameter is missing
        return false if args.empty?

        args.shift if args.first.type != :splat
      end

      if args.empty?
        params[:keyreq] == nil
      else
        with_kwsplat = false
        keyword_args = {}

        if args.last.type == :hash
          keyword_args = args.pop.children.each.with_object({}) do |pair, hash|
            case pair.type
            when :pair
              if pair.children[0].type == :sym
                hash[pair.children[0].children[0]] = true
              end
            when :kwsplat
              with_kwsplat = true
            end
          end
        end

        # test if all required keyword params are given
        Array(params[:keyreq]).each do |pair|
          unless keyword_args.delete(pair.last)
            # required keyword is not given
            unless with_kwsplat
              return false
            end
          end
        end

        if params[:keyrest]
          true
        else
          # consume optional keywords
          Array(params[:key]).each do |pair|
            keyword_args.delete(pair.last)
          end

          # !keyword_args.empty? means there is unexpected arg

          if keyword_args.empty?
            if args.empty? || params[:rest] || args.first.type == :splat
              true
            else
              Array(params[:opt]).count >= args.count
            end
          else
            false
          end
        end
      end
    end
  end
end
