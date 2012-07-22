require 'pione/common'

module Pione
  module Rule
    class SystemHandler < BaseHandler
      def execute
        @rule.body.call(tuple_space_server)
      end
    end
  end
end
