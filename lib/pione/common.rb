require 'set'
require 'uuidtools'
require 'socket'
require 'digest'
require 'socket'
require 'drb/drb'
require 'rinda/rinda'
require 'rinda/tuplespace'
require 'json'
require 'tempfile'

module Pione
  @@debug_mode = false
  @@quiet_mode = false

  def debug_mode
    orig = @@debug_mode
    @@debug_mode = true
    yield
    @@debug_mode = orig
  end
  module_function :debug_mode

  # Change debug mode true or not.
  def debug_mode=(mode)
    @@debug_mode = mode
  end
  module_function :debug_mode=

  # Return true if the system is debug mode.
  def debug_mode?
    @@debug_mode
  end
  module_function :debug_mode?

  def quiet_mode
    orig = @@quiet_mode
    @@quiet_mode = true
    yield
    @@quiet_mode = orig
  end
  module_function :debug_mode

  def quiet_mode=(mode)
    @@quiet_mode = mode
  end
  module_function :quiet_mode=

  def quiet_mode?
    @@quiet_mode
  end
  module_function :quiet_mode?

  def debug_message(msg)
    if debug_mode? and not(quiet_mode?)
      puts "%s: %s" % [Terminal.magenta("debug"), msg]
    end
  end

  def user_message(msg)
    if not(quiet_mode?)
      puts "%s: %s" % [Terminal.red("user"), msg]
    end
  end

  # Start finalization process for Pione world.
  def finalize
    # finalize all innocent white objects
    ObjectSpace.each_object(PioneObject) do |obj|
      obj.finalize
    end
    # system exit
    exit
  end
  module_function :finalize

  module Terminal
    @@color_mode = true

    def color_mode=(bool)
      @@color_mode = bool
    end
    module_function :color_mode=

    def red(str)
      colorize(str, "\x1b[31m", "\x1b[39m")
    end
    module_function :red

    def green(str)
      colorize(str, "\x1b[32m", "\x1b[39m")
    end
    module_function :green

    def magenta(str)
      colorize(str, "\x1b[35m", "\x1b[39m")
    end
    module_function :magenta

    def colorize(str, bc, ec)
      @@color_mode ? bc + str + ec : str
    end
    module_function :colorize
  end

  # Basic object class of pione system.
  class PioneObject
    def uuid
      @__uuid__ ||= Util.uuid
    end

    # Finalize the object.
    def finalize
      # do nothing
    end
  end

  # Utility functions for pione system.
  module Util
    # Set signal trap for the system.
    def self.set_signal_trap
      finalizer = Proc.new { finalize }
      Signal.trap(:INT, finalizer)
    end

    # Generate UUID.
    def self.uuid
      UUIDTools::UUID.random_create.to_s
    end

    # Ignore all exceptions of the block execution.
    def self.ignore_exception(&b)
      begin
        b.call
      rescue Exception
        # do nothing
      end
    end

    # Return hostname of the machine.
    def self.hostname
      Socket.gethostname
    end

    # Make task_id by input data names.
    def self.task_id(inputs, params)
      raise ArgumentError.new(params) unless params.kind_of?(Parameters)
      # FIXME: inputs.flatten?
      input_names = inputs.flatten.map{|t| t.name}
      is = input_names.join("\000")
      ps = params.data.map do |key, val|
        "%s:%s" % [key.task_id_string,val.task_id_string]
      end.join("\000")
      Digest::MD5.hexdigest("#{is}\001#{ps}\001")
    end

    # Make target domain name by module name, inputs, and outputs.
    def self.domain(package_name, rule_name, inputs, params)
      "%s-%s_%s" % [package_name, rule_name, task_id(inputs, params)]
    end
  end
end

require 'pione/model'
require 'pione/agent'
require 'pione/tuple-space-server-interface'
require 'pione/agent/tuple-space-client'
require 'pione/tuple-space-server'
require 'pione/log'
require 'pione/tuple'
require 'pione/data-finder'
require 'pione/document'
require 'pione/update-criteria'
require 'pione/rule-handler'
require 'pione/agent/command-listener'
require 'pione/agent/task-worker'

module Pione
  include Pione::Model
end
