require 'innocent-white/common'

module InnocentWhite
  class Document
    class Transformer < Parslet::Transform
      class UnknownAttribution < Exception
        def initialize(t, identifier)
          @t = t
          @identifier = identifier
        end
        def message
          "Unknown identifier '#{@identifier}' in the context of #{@t}"
        end
      end

      def initialize(data={})
        super()
        @package = data[:package]
      end

      #
      # common
      #

      # data_name
      # escape characters are substituted
      rule(:data_name => simple(:name)) {
        name.to_s.gsub(/\\(.)/) {$1}
      }

      # string
      rule(:string => simple(:s)) { s }

      #
      # statement
      #

      # package
      rule(:package => subtree(:tree)) {
        Package.new(tree[:package_name].to_s)
      }

      #
      # rule
      #
      rule(:rule_definition => subtree(:tree)) {
        name = tree[:rule_header][:rule_name].to_s
        inputs = tree[:inputs]
        outputs = tree[:outputs]
        params = tree[:params]
        flow_block = tree[:flow_block]
        action_block = tree[:action_block]
        if flow_block
          Rule::FlowRule.new(@package, name, inputs, outputs, params, flow_block)
        else
          body = action_block[:body].to_s
          Rule::ActionRule.new(@package, name, inputs, outputs, params, body)
        end
      }

      #
      # rule conditions
      #

      # input_line
      rule(:input_line => subtree(:input)) {
        data_expr = input[:data]
        if input[:input_header] == "input-all"
          data_expr.all
        else
          data_expr
        end
      }

      # output_line
      rule(:output_line => subtree(:output)) {
        data_expr = output[:data]
        if output[:output_header] == "output-all"
          data_expr.all
        else
          data_expr
        end
      }

      # param_line
      rule(:param_line => subtree(:param)) {
        param[:variable].to_s
      }

      #
      # expression
      #

      # data_expr
      rule(:data_expr => subtree(:tree)) {
        data_name = tree[:data_name].to_s.gsub(/\\(.)/) {$1}
        elt = DataExpr.new(data_name)
        tree[:attributions].each do |attr|
          attribution_name = attr[:attribution_name]
          arguments = attr[:arguments]
          case attribution_name.to_s
          when "except"
            elt.except(*arguments)
          when "stdout"
            elt.stdout
          else
            raise UnknownAttribution.new('data', identifier)
          end
        end
        elt
      }

      # rule_expr
      rule(:rule_expr => subtree(:tree)) {
        rule_name = tree[:rule_name].to_s
        elt = RuleExpr.new(@package, rule_name)
        tree[:attributions].each do |attr|
          attribution_name = attr[:attribution_name]
          arguments = attr[:arguments]
          begin
            elt.set_attribution(attribution_name.to_s, arguments)
          rescue UnknownRuleExprAttribution
            raise UnknownAttribution.new('rule', attribution_name)
          end
        end
        elt
      }

      #
      # flow element
      #

      rule(:call_rule => subtree(:tree)) {
        rule_expr = tree[:rule_expr]
        Rule::FlowElement::CallRule.new(rule_expr)
      }

      #
      # condition
      #
      rule(:if_block => subtree(:block)) {
        variable = block[:variable].to_s
        true_elements = block[:true_elements]
        else_elements = block[:else_elements]
        block = {true => true_elements, :else => else_elements}
        Rule::FlowElement::Condition.new(variable, block)
      }

      rule(:case_block => subtree(:case_block)) {
        variable = case_block[:variable].to_s
        block = {}
        case_block[:when_block].each do |t|
          block[t[:when].to_s] = t[:elements]
        end
        block[:else] = case_block[:else_elements]
        Rule::FlowElement::Condition.new(variable, block)
      }
    end
  end
end
