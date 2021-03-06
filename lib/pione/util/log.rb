module Pione
  module Util
    # Log is a representation for logging.
    # @example
    #   Log.new do
    #     add_record(
    #       component: "tuple-space-server",
    #       key: "action",
    #       value: "start"
    #     )
    #   end
    #
    class Log
      # Log::Record is a key-value line for log. A record consisted of following items:
      # - application
      # - component
      # - key
      # - value
      class Record
        attr_reader :components
        attr_reader :key
        attr_reader :value

        # Creates a log record.
        def initialize(components, key, value)
          @components = components.kind_of?(Array) ? components : [components]
          @key = key
          @value = value
        end

        def application
          "" # "pione"
        end

        # Format as a string.
        # i.e.
        #   2012-04-25T14:48:57.791+09:00 A35D pione.rule-provider.status: initialized
        def format(logid, time)
          resource = [application, components, key].flatten.compact.join(".")
          "%s %s %s: %s" % [time, logid, resource, value.to_json]
        end
      end

      attr_reader :records

      # Creatas a new log record.
      def initialize
        @records = []
        yield self if block_given?
      end

      def add_record(*args)
        @records << Record.new(*args)
      end

      def timestamp=(time)
        @time = time
      end

      # Format as string.
      # i.e.
      #   2012-04-25T14:48:57.791+09:00 A35D .task-worker.action: "take_task"
      #   2012-04-25T14:48:57.791+09:00 A35D .task-worker.object: ...
      def format
        logid = generate_logid
        time = @time.iso8601(3)
        @records.map{|record| record.format(logid, time)}.join("\n")
      end

      private

      IDCHAR = ("A".."Z").to_a + (0..9).to_a.map{|i|i.to_s}

      def generate_logid(i=4)
        i > 0 ? IDCHAR[rand(IDCHAR.size)] + generate_logid(i-1) : ""
      end
    end
  end
end
