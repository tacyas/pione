require_relative '../test-util'

class TestParser < Parslet::Parser
  include Pione::Parser::FeatureExprParser
end

describe 'Pione::Parser::FeatureExprParser' do
  describe 'feature_expr' do
    it 'should parse feature expressions' do
      strings = ['+A', '-A', '?A', '(+A)',
                 '+A & +A', '+A | +A', '?A & +A',
                 '(+A) & (+A)', '(+A | +A)',
                 '+A & (+A & -A)', '(+A & -A) & +A']
      strings.each do |s|
        should.not.raise(Parslet::ParseFailed) do
          TestParser.new.feature_expr.parse(s)
        end
      end
    end

    TestUtil::Parser.spec(Pione::Parser::FeatureExprParser, __FILE__, self)

    it 'should fail with other strings' do
      strings = ['A', '(-A', '?A)']
      strings.each do |s|
        should.raise(Parslet::ParseFailed) do
          TestParser.new.feature_expr.parse(s)
        end
      end
    end
  end
end
