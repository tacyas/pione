require 'pione'
require 'pione/agent'

module Pione
  module Agent
    class Logger < TupleSpaceClient
      set_agent_type :logger

      def initialize(ts_server, out=$stdout)
        super(ts_server)
        @out = out
      end

      define_state :logging

      define_state_transition :initialized => :logging
      define_state_transition :logging => :logging

      define_exception_handler ThreadError => :terminated

      # Sleep till the logger clears logs.
      def wait_to_clear_logs(timespan=0.1)
        while count_tuple(Tuple[:log].any) > 0
          sleep timespan
        end
      end

      private

      # State logging.
      def transit_to_logging
        log = take(Tuple[:log].any)
        @out.puts log.message.format
        @out.flush
        @out.sync
      end

      # State terminated.
      def transit_to_terminated
        super
        unless @out == STDOUT
          Util.ignore_exception { @out.close }
        end
      end
    end

    set_agent Logger
  end
end