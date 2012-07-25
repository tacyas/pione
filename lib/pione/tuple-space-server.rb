require 'pione/common'
require 'pione/tuple-space-provider'

module Pione
  module TupleSpaceServerMethod
    def self.tuple_space_interface(name, opt={})
      define_method(name) do |*args, &b|
        # convert tuple space form
        _args = args.map do |obj|
          tuple_form = obj.respond_to?(:to_tuple_space_form)
          tuple_form ? obj.to_tuple_space_form : obj
        end
        # check arguments
        if opt.has_key?(:validator)
          opt[:validator].call(args)
        end
        # send a message to the tuple space
        result = @ts.__send__(name, *_args, &b)
        # convert the result to tuple object
        if converter = opt[:result]
          converter.call(result)
        else
          result
        end
      end
    end

    # Define tuple space interfaces.
    tuple_space_interface :read, :result => lambda{|t| Tuple.from_array(t)}
    tuple_space_interface :read_all, :result => lambda{|list| list.map{|t| Tuple.from_array(t)}}
    tuple_space_interface :take, :result => lambda{|t| Tuple.from_array(t)}
    tuple_space_interface :write, :validator => Proc.new {|*args|
      args.first.writable? if args.first.kind_of?(Tuple::TupleObject)
    }
    tuple_space_interface :notify
  end

  class TupleSpaceServer < PioneObject
    include DRbUndumped
    include TupleSpaceServerMethod

    attr_reader :tuple_space

    def initialize(data={})
      @__ts__ = Rinda::TupleSpace.new
      @tuple_space = @__ts__
      @ts = Rinda::TupleSpaceProxy.new(@__ts__)
      def @ts.to_s;"#<Rinda::TupleSpace>" end

      # check task worker resource
      resource = data[:task_worker_resource] || 1
      write(Tuple[:task_worker_resource].new(number: resource))

      @terminated = false
      @provider_options = {} ## FIXME

      # base uri
      if data.has_key?(:base_uri)
        uri = data[:base_uri]
        write(Tuple[:base_uri].new(uri: uri))
      end

      # agents
      @life_keeper = Agent::TupleSpaceServerLifeKeeper.start(self)
      @life_keeper.wait_till(:sleeping)
      @client_life_checker = Agent::TupleSpaceServerClientLifeChecker.start(self)
    end

    def alive?
      not(@terminated)
    end

    # Return pid
    def pid
      Process.pid
    end

    def now
      Time.now
    end

    # Return common base uri of the space.
    def base_uri
      URI(read(Tuple[:base_uri].any).uri)
    end

    # Return the worker resource size of the server.
    def task_worker_resource
      read(Tuple[:task_worker_resource].any).number
    end

    # Return the number of tuples matched with specified tuple.
    def count_tuple(tuple)
      read_all(tuple).size
    end

    # Return the current worker size of the server.
    def current_task_worker_size
      tuple = Tuple[:agent].any
      tuple.agent_type = :task_worker
      read_all(tuple).size
    end

    # Return all tuples of the tuple space.
    def all_tuples
      tuples = []
      bag = @__ts__.instance_variable_get("@bag")
      bag.instance_variable_get("@hash").values.each do |bin|
        tuples += bin.instance_variable_get("@bin")
      end
      _tuples = tuples.map{|t| t.value}
      return _tuples
    end

    # Shutdown the server.
    def finalize
      @terminated = true
      write(Tuple[:command].new("terminate"))
      @life_keeper.terminate
      @life_keeper.running_thread.join
      @client_life_checker.terminate
      @client_life_checker.running_thread.join
      sleep 1
    end

    alias :terminate :finalize
  end
end

require 'pione/agent'
require 'pione/agent/tuple-space-server-life-keeper'
require 'pione/agent/tuple-space-server-client-life-checker'
