require 'innocent-white/util'
require 'innocent-white/tuple'
require 'innocent-white/tuple-space-server'

module InnocentWhite
  class AgentStatus
    def self.define_state(state)
      # define self.#{state} by singleton class
      singleton_class = class << self; self; end
      singleton_class.instance_eval do
        define_method(state){new(state)}
      end
      # define accessors
      define_method(state){@state = state}
      define_method("#{state}?"){state === self}
      # add state list
      @state_list = [] if @state_list.nil?
      @state_list << state
    end

    def self.define_sub_state(parent, child)
      if state_list.include?(parent)
        define_state(child)
        @rel = {} if @rel.nil?
        @rel[child] = parent
      else
        raise ArgumentError
      end
    end

    def self.state_list
      list = (@state_list || [] )
      superclass.respond_to?(:state_list) ? superclass.state_list + list : list
    end

    define_state :initialized
    define_state :running
    define_state :stopped
    define_state :terminated

    attr_reader :state

    def initialize(state = :initialized)
      if self.class.state_list.include?(state)
        @state = state
      else
        raise ArgumentError
      end
    end

    def parent
      state = @state
      self.class.module_eval {begin @rel[state] rescue nil end}
    end

    def parent?(other)
      parent ? parent == other : false
    end

    def ancestor?(target)
      if parent
        parent?(target) || self.class.new(parent).ancestor?(target)
      else
        false
      end
    end

    def ==(other)
      if other.kind_of?(AgentStatus)
        @state == other.state
      else
        @state == other
      end
    end

    alias :eql? :==

    def hash
      @state.hash
    end

    def ===(other)
      other = other.state if other.kind_of?(AgentStatus)
      @state == other || ancestor?(other)
    end
  end

  module Agent
    TABLE = Hash.new

    # Return a class for agent type.
    def self.[](type)
      TABLE[type]
    end

    # Set a agent of the system.
    def self.set_agent(klass)
      TABLE[klass.agent_type] = klass
    end

    class Base
      # -- class methods --

      # Set the agent type.
      def self.set_agent_type(agent_type)
        @agent_type = agent_type
      end

      # Return the agent type.
      def self.agent_type
        @agent_type
      end

      def self.set_status_class(klass)
        @status_class = klass
      end

      def self.status_class
        @status_class || AgentStatus
      end

      # -- instance methods --

      attr_reader :status
      attr_reader :thread
      attr_reader :agent_id
      attr_reader :agent_type

      # Initialize agent's state.
      def initialize(ts_server)
        @status = self.class.status_class.initialized
        @__runnable__ = nil
        @agent_id = Util.uuid
        @tuple_space_server = ts_server
      end

      def hello
        puts "hello #{@tuple_space_server}" if $DEBUG
        @tuple_space_server.write(self.to_agent_tuple)
      end

      def bye
        puts "bye #{@tuple_space_server}" if $DEBUG
        @tuple_space_server.take(self.to_agent_tuple, 0.1)
      end

      # Stop the agent.
      def stop
        @__runnable__ = false
        Thread.new do
          @thread.join
          @status.stopped
        end
      end

      # Kill current running thread and move to tuple space.
      def move_tuple_space_server(tuple_space_server)
        bye()
        @__next_tuple_space_server__ = tuple_space_server
        # kill running thread and wait to exit
        @thread.kill
        @thread.join
        # restart running thread
        start_running
        while not(@__next_tuple_space_server__.nil?) do
          sleep 0.01
        end
      end

      # Convert a agent tuple.
      def to_agent_tuple
        Tuple[:agent].new(agent_type: self.class.agent_type,
                          agent_id: @agent_id)
      end

      private

      # Start the action.
      def start_running
        return nil if not(@thread.nil?) and not(@thread.stop?)
        @thread = Thread.new do
          # start
          @status.running
          @__runnable__ = true

          # job loop
          while @__runnable__ do
            # set tuple space
            if @__next_tuple_space_server__
              ts = @__next_tuple_space_server__
              @__next_tuple_space_server__ = nil
              @tuple_space_server = ts
              hello()
            end

            # do agent job
            run
          end
        end
      end
    end
  end
end

class Symbol
  alias :__eq3_orig__ :===

  def ===(other)
    if other.kind_of?(InnocentWhite::AgentStatus)
      other === self
    else
      __eq3_orig__(other)
    end
  end
end