module Pione
  # RuleHandler is a handler for rule execution.
  module RuleHandler
    # Exception class for rule execution failure.
    class RuleExecutionError < StandardError
      def initialize(handler)
        @handler = handler
      end

      def message
        "Execution error when handling the rule '%s': inputs=%s, output=%s, params=%s" % [
          @handler.rule.rule_path,
          @handler.inputs,
          @handler.outputs,
          @handler.params.inspect
        ]
      end
    end

    class UnknownRule < StandardError; end

    # BasicHandler is a base class for rule handlers.
    class BasicHandler
      include TupleSpaceServerInterface

      attr_reader :rule
      attr_reader :inputs
      attr_reader :outputs
      attr_reader :params
      attr_reader :base_uri
      attr_reader :task_id
      attr_reader :domain
      attr_reader :variable_table
      attr_reader :call_stack

      # Create a new handler for rule.
      # @param [TupleSpaceServer] ts_server
      #   tuple space server
      # @param [Rule] rule
      #   rule instance
      # @param [Array<Data,Array<Data>>] inputs
      #   input tuples
      # @param [Hash] opts
      #   optionals
      def initialize(ts_server, rule, inputs, params, call_stack, opts={})
        # check arguments
        raise ArgumentError.new(inputs) unless inputs.kind_of?(Array)
        raise ArgumentError.new(inputs) unless inputs.size == rule.inputs.size
        raise ArgumentError.new(params) unless params.kind_of?(Parameters)

        # set tuple space server
        set_tuple_space_server(ts_server)

        # set informations
        @rule = rule
        @inputs = inputs
        @outputs = []
        @params = @rule.params.merge(params)
        @original_params = params
        @content = rule.body
        @domain = get_handling_domain(opts)
        @variable_table = VariableTable.new(@params.data)
        @base_uri = read(Tuple[:base_uri].any).uri
        @dry_run = begin read0(Tuple[:dry_run].any).availability rescue false end
        @task_id = ID.task_id(@inputs, @params)
        @call_stack = call_stack

        setup_variable_table
      end

      # Puts environment variable into pione variable table.
      # @param [Hash{String => String}] env
      #   environment table
      # @return [void]
      def setenv(env)
        env.each do |key, value|
          @variable_table.set(Variable.new("ENV_" + key), PioneString.new(value))
        end
      end

      # Handles the rule and returns the outputs.
      # @return [Array<Data,Array<Data>>]
      #   outputs
      def handle
        name = self.class.message_name

        # show begin message
        user_message_begin("Start %s Rule: %s" % [name, handler_digest])

        # call stack
        debug_message("call stack:")
        @call_stack.each_with_index do |domain, i|
          debug_message("%s:%s" % [i, domain], 1)
        end

        # execute the rule
        outputs = execute

        # show output list
        debug_message("%s Rule %s Result:" % [name, handler_digest])

        @outputs.compact.each_with_index do |output, i|
          if output.kind_of?(Array)
            output.each_with_index do |o, ii|
              debug_message("%s,%s:%s" % [i, ii, o.name], 1)
            end
          else
            debug_message("%s:%s" % [i, output.name], 1)
          end
        end

        # show end message
        user_message_end "End %s Rule: %s" % [name, handler_digest]

        return outputs.compact
      end

      # Returns true if it is root rule handler.
      # @return [Boolean]
      #   true if it is root rule handler
      def root?
        self.kind_of?(RootHandler)
      end

      # @api private
      def ==(other)
        return false unless @rule == other.rule
        return false unless @inputs == other.inputs
        return false unless @outputs == other.outputs
        return false unless @params == other.params
        return true
      end

      # @api private
      alias :eql? :==

      # @api private
      def hash
        @rule.hash + @inputs.hash + @outputs.hash + @params.hash
      end

      private

      # Executes the rule.
      # @return [Array<Data,Array<Data>>]
      #   outputs
      # @api private
      def execute
        raise NotImplementError
      end

      # Return the domain.
      def get_handling_domain(opts)
        opts[:domain] || ID.domain_id(
          @rule.expr.package.name,
          @rule.expr.name,
          @inputs,
          @original_params
        )
      end

      # Makes resource uri.
      def make_resource_uri(name, domain)
        if domain == "root" || domain.nil?
          return URI.parse(@base_uri) + "./%s" % name
        else
          # make relative path
          rule_name = domain.split("_")[0..-2].join("_")
          digest = domain.split("_").last
          path = "./.%s/%s/%s" % [rule_name, digest, name]

          # make uri
          return URI.parse(@base_uri) + path
        end
      end

      # Makes output resource uri.
      def make_output_resource_uri(name)
        # get parent domain or root domain
        make_resource_uri(name, @call_stack.last)
      end

      # Make output tuple by name.
      def make_output_tuple(name)
        uri = make_output_resource_uri(name).to_s
        Tuple[:data].new(name: name, domain: @domain, uri: uri, time: nil)
      end

      # Setup variable table. The following variables are introduced in variable
      # table:
      # - input auto variables
      # - output auto variables
      def setup_variable_table
        @variable_table.make_input_auto_variables(@rule.inputs, @inputs)
        outputs = @rule.outputs.map {|expr| expr.eval(@variable_table) }
        output_tuples = outputs.map {|expr| make_output_tuple(expr.name) }
        @variable_table.make_output_auto_variables(outputs, output_tuples)
      end

      # Returns digest string of this handler.
      def handler_digest
        params = @params.data.select{|k,_|
          not(k.toplevel?)
        }.map{|k,v| "%s:%s" % [k.name, v.textize]}.join(",")
        "%s([%s],{%s})" % [
          @rule.rule_path,
          @inputs.map{|i|
            i.kind_of?(Array) ? "[%s, ...]" % i[0].name : i.name
          }.join(","),
          params
        ]
      end

    end
  end
end

