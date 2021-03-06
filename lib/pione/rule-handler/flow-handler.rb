module Pione
  module RuleHandler
    # FlowHandler represents a handler for flow actions.
    class FlowHandler < BasicHandler
      def self.message_name
        "Flow"
      end

      # @api private
      def initialize(*args)
        super
        @data_finder = DataFinder.new(tuple_space_server, @domain)
        @finished = []
      end

      # Starts to process flow elements. This processes rule application, output
      # search, resource shift, and output validation.
      # @return [void]
      def execute
        # restore data tuples from resource
        restore_data_tuples_from_resource
        # rule application
        apply_rules(@rule.body.eval(@variable_table).elements)
        # find outputs
        find_outputs
        # shift resource
        shift_output_resources
        # check output validation
        validate_outputs

        return @outputs
      end

      private

      # Restores data tuples from the domain resource.
      # @return [void]
      def restore_data_tuples_from_resource
        uri = root? ? @base_uri : @base_uri + (".%s/%s" % @domain.split("_"))
        if Resource[uri].exist?
          Resource[uri].entries.each do |res|
            write(Tuple[:data].new(@domain, res.basename, res.uri.to_s, res.mtime))
          end
        end
      end

      # Applies target input data to rules.
      # @param [Array<CallRule>] callees
      #   elements of call rule lines
      # @return [void]
      def apply_rules(callees)
        user_message_begin("Start Rule Application: %s" % handler_digest)

        # apply flow-element rules
        while true do
          # find updatable rule applications
          applications = select_updatables(find_applicable_rules(callees))

          unless applications.empty?
            # push task tuples into tuple space
            distribute_tasks(applications)
          else
            break # finish applications
          end
        end

        user_message_end("End Rule Application: %s" % handler_digest)
      end

      # Finds applicable flow-element rules with inputs and variables.
      def find_applicable_rules(callees)
        callees.inject([]) do |combinations, callee|
          # eval callee expr by handling rule context
          callee = callee.eval(@variable_table)

          # find callee rule
          rule = find_callee_rule(callee)

          # update callee parameters
          @variable_table.variables.each do |var|
            val = @variable_table.get(var)
            unless val == UndefinedValue.new
              if rule.params.keys.include?(var)
                callee.expr.params.set_safety!(var, val)
              end
            end
          end

          # eval callee rule by the context
          vtable = callee.expr.params.eval(@variable_table).as_variable_table
          rule = rule.eval(vtable)

          # check rule status and find combinations
          @data_finder.find(:input, rule.inputs, vtable).each do |res|
            combinations << [
              callee,
              rule,
              res.combination,
              res.variable_table
            ]
          end

          # find next
          combinations.uniq
        end
      end

      # Finds the rule of the callee.
      def find_callee_rule(callee)
        return read(Tuple[:rule].new(rule_path: callee.rule_path), 0).content
      rescue Rinda::RequestExpiredError
        debug_message "Request loading a rule #{callee.rule_path}"
        write(Tuple[:request_rule].new(callee.rule_path))
        tuple = read(Tuple[:rule].new(rule_path: callee.rule_path))

        # check whether known or unknown
        if tuple.status == :known
          return tuple.content
        else
          raise UnknownRule.new(callee.rule_path)
        end
      end

      # Finds inputs and variables for flow element rules.
      def select_updatables(combinations)
        combinations.select do |callee, rule, inputs, vtable|
          # task domain
          task_domain = ID.domain_id3(rule, inputs, callee)

          # import finished tuples's data
          import_finished_outputs(task_domain)

          # find outputs combination
          outputs_combination = @data_finder.find(
            :output,
            rule.outputs.map{|output| output.eval(vtable)},
            vtable
          ).map{|r| r.combination }

          # no outputs combination means empty list
          outputs_combination = [[]] if outputs_combination.empty?

          # check update criterias
          outputs_combination.any?{|outputs|
            UpdateCriteria.satisfy?(rule, inputs, outputs, vtable)
          }
        end
      end

      # Distributes tasks.
      # @param [Array] applications
      #   application informations
      # @return [void]
      def distribute_tasks(applications)
        user_message_begin("Start Task Distribution: %s" % handler_digest)
        canceled = []

        applications.uniq.each do |callee, rule, inputs, vtable|
          # task domain
          task_domain = ID.domain_id3(rule, inputs, callee)

          # make a task tuple
          task = Tuple[:task].new(
            rule.rule_path,
            inputs,
            callee.expr.params,
            rule.features,
            task_domain,
            @call_stack + [@domain] # current call stack + caller
          )

          # check if same task exists
          begin
            if need_task?(task)
              # copy input data from the handler domain to task domain
              copy_data_into_domain(inputs, task_domain)

              # write the task
              write(task)

              msg = "distributed task %s on %s" % [task.digest, handler_digest]
              user_message(msg, 1)

              next
            end
          rescue Rinda::RedundantTupleError
            # ignore
          end

          show "cancel task %s on %s" % [task.digest, handler_digest]
          canceled << task_domain
        end

        # wait to finish threads
        applications.uniq.each do |callee, rule, inputs, vtable|
          # task domain
          task_domain = ID.domain_id3(rule, inputs, callee)

          # wait to finish the work
          template = Tuple[:finished].new(
            domain: task_domain,
            status: :succeeded
          )
          finished = read(template)

          unless canceled.include?(task_domain)
            msg = "finished task %s on %s" % [finished.domain, handler_digest]
            user_message(msg, 1)
          end

          # copy data from task domain to this domain
          @finished << finished
          copy_data_into_domain(finished.outputs, @domain)
        end

        user_message_end("End Task Distribution: %s" % handler_digest)
      end

      # Returns true if we need to write the task into the tuple space.
      # @param [Task] task
      #   task tuple
      # @return [Boolean]
      #   true if we need to write the task into the tuple space
      def need_task?(task)
        not(exist_task?(task) or working?(task))
      end

      # Returns true if the task exists in the tuple space already.
      # @param [Task] task
      #   task tuple
      # @return [Boolean]
      #   true if the task exists in the tuple space already
      def exist_task?(task)
        read0(task)
        return true
      rescue Rinda::RequestExpiredError
        return false
      end

      # Returns true if any task worker is working on the task.
      # @param [Task] task
      #   task tuple
      # @return [Boolean]
      #   true if any task worker is working on the task
      def working?(task)
        read0(Tuple[:working].new(domain: task.domain))
        return true
      rescue Rinda::RequestExpiredError
        return false
      end

      # Find outputs from the domain.
      # @return [void]
      def find_outputs
        @rule.outputs.each_with_index do |output, i|
          output = output.eval(@variable_table)
          tuples = read_all(Tuple[:data].new(domain: @domain))
          case output.modifier
          when :all
            @outputs[i] = tuples.find_all {|data| output.match(data.name)}
          when :each
            @outputs[i] = tuples.find {|data| output.match(data.name)}
          end
        end
      end

      # Shifts output resource locations.
      # @return [void]
      def shift_output_resources
        # cheker for double shift
        shifted = []
        # shift output resources
        @outputs.flatten.compact.each do |output|
          old_uri = URI.parse(output.uri)
          new_uri = URI.parse(make_output_resource_uri(output.name).to_s)
          unless new_uri.path == old_uri.path or shifted.include?(old_uri.path)
            # shift resource
            Resource[new_uri].shift_from(Resource[old_uri])
            # shift cache if the old is cached in this machine
            FileCache.shift(old_uri, new_uri)
            # write shift tuple
            write(Tuple[:shift].new(old_uri.to_s, new_uri.to_s))
            # push moved path
            shifted << old_uri.path
          end
        end
      end

      # Validates outputs size.
      def validate_outputs
        # size check
        if @rule.outputs.size > 0 and not(@rule.outputs.size == @outputs.size)
          raise RuleExecutionError.new(self)
        end
        # nil check
        if @outputs.any?{|tuple| tuple.nil?}
          raise RuleExecutionError.new(self)
        end

        # empty list check
        if @outputs.any?{|tuple| tuple.kind_of?(Array) && tuple.empty?}
          raise RuleExecutionError.new(self)
        end
      end

      # Imports finished tuple's outputs from the domain.
      # @param [String] task_domain
      #   target task domain
      # @return [void]
      def import_finished_outputs(task_domain)
        return if @finished.any?{|t| t.domain == task_domain}
        if task_domain != @domain
          template = Tuple[:finished].new(
            domain: task_domain,
            status: :succeeded
          )
          finished = read0(template)
          copy_data_into_domain(finished.outputs, @domain)
        end
      rescue Rinda::RequestExpiredError
        # ignore
      end

      # Copy data into specified domain and return the tuple list
      def copy_data_into_domain(src_data, dest_domain)
        src_data.flatten.compact.map do |d|
          new_data = d.clone
          new_data.domain = dest_domain
          begin
            write(new_data)
          rescue Rinda::RedundantTupleError
            # ignore
          end
          new_data
        end
      end
    end
  end
end
