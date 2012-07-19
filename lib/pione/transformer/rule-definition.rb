class Pione::Transformer
  module RuleDefinition
    include Pione::TransformerModule

    def check_model_type(obj, pione_model_type)
      pione_model_type.match(obj.pione_mode_type)
    end
    module_function :check_model_type

    # rule_definition
    rule(:rule_definition => {
           :rule_header => simple(:rule_expr),
           :rule_conditions => sequence(:conditions),
           :block => simple(:block) }) {
      inputs = conditions.select{|c| c.type == :input}.map{|c| c.obj}
      outputs = conditions.select{|c| c.type == :output}.map{|c| c.obj}
      params = conditions.select{|c| c.type == :param}.map{|c| c.obj}
      features = conditions.select{|c| c.type == :feature}.map{|c| c.obj}
      condition = RuleCondition.new(inputs, outputs, params, features)
      case block
      when ActionBlock
        ActionRule
      when FlowBlock
        FlowRule
      end.new(rule_expr, condition, block)
    }

    ConditionLine = Struct.new(:type, :obj)

    # input_line
    rule(:input_line => simple(:data_expr)) {
      TypeDataExpr.check(data_expr)
      ConditionLine.new(:input, data_expr)
    }

    # output_line
    rule(:output_line => simple(:data_expr)) {
      TypeDataExpr.check(data_expr)
      ConditionLine.new(:output, data_expr)
    }

    # param_line
    rule(:param_line => simple(:variable)) {
      TypeAny.check(variable)
      ConditionLine.new(:param, variable)
    }

    # feature_line
    rule(:feature_line => simple(:feature_expr)) {
      TypeFeatureExpr.check(feature_expr)
      ConditionLine.new(:feature, feature_expr)
    }
  end
end
