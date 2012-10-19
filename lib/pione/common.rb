module Pione
  # Starts finalization process for PIONE system.
  # @return [void]
  def finalize
    # finalize all innocent white objects
    ObjectSpace.each_object(PioneObject) do |obj|
      obj.finalize
    end
    # system exit
    exit
  end
  module_function :finalize

  # Sets signal trap for the system.
  # @return [void]
  def set_signal_trap
    finalizer = Proc.new { finalize }
    Signal.trap(:INT, finalizer)
  end
  module_function :set_signal_trap

  # Ignores all exceptions of the block execution.
  # @yield []
  #   target block
  # @return [void]
  def ignore_exception(&b)
    begin
      b.call
    rescue Exception
      # do nothing
    end
  end

  # Generates UUID.
  # @return [String]
  #   generated UUID string
  # @note
  #   we use uuidtools gem for generating UUID
  def self.generate_uuid
    UUIDTools::UUID.random_create.to_s
  end

  # Returns the hostname of the machine.
  # @return [String]
  #   hostname
  def get_hostname
    Socket.gethostname
  end
  module_function :get_hostname

  def self.get_core_number
    begin
      `cat /proc/cpuinfo | grep processor | wc -l`.to_i
    rescue
      1
    end
  end
end
