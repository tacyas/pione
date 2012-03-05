require 'innocent-white/common'

module InnocentWhite
  class TupleSpaceProvider < InnocentWhiteObject
    include DRbUndumped
    include MonitorMixin

    UDP_PORT = 54321
    PROVIDER_URI = "druby://localhost:10101"
    TIMEOUT = 5

    # -- class  --

    # Return the provider instance.
    def self.instance(data = {})
      uri = if data.has_key?(:provider_port)
              "druby://localhost:#{data[:provider_port]}"
            else
              PROVIDER_URI
            end
      # check DRb service
      begin
        DRb.current_server
      rescue
        DRb.start_service
      end
      # remote object
      begin
        # get provider reference
        provider = DRbObject.new_with_uri(uri)
        provider.uuid # check the server exists
        provider
      rescue
        begin
          # create new provider
          puts ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
          provider = self.new(data)
          provider.drb_service = DRb::DRbServer.new(uri, provider)
          DRbObject.new_with_uri(uri)
        rescue Errno::EADDRINUSE
          # retry
          instance(data)
        end
      end
    end

    # -- instance --

    attr_accessor :timeout
    attr_accessor :receiver_port
    attr_accessor :drb_service

    def initialize(data={})
      raise ArgumentError if (data.keys - [:provider_port, :udp_port, :timeout]).size > 0

      super()

      @expiration_time = 5
      @timeout = data.has_key?(:timeout) ? data[:timeout] : TIMEOUT
      @udp_port = data.has_key?(:udp_port) ? data[:udp_port] : UDP_PORT
      @tuple_space_servers = []
      @remote_object = Marshal.dump(DRbObject.new(self))
      @terminated = false

      keep_connection
      keep_clean
    end

    def alive?
      not(@terminated)
    end

    # Add the tuple space server.
    def add(remote_object_uri)
      synchronize do
        obj = DRbObject.new_with_uri(remote_object_uri)
        @tuple_space_servers[obj] = Time.now
      end
    end

    # Return the process provider's current pid
    def pid
      Process.pid
    end

    # Return tuple space servers.
    def tuple_space_servers
      synchronize do
        @tuple_space_servers.keys
      end
    end

    # Send empty tuple space server list.
    def finalize
      @terminated = true
      DRb.remove_server(@drb_service)
      @thread_keep_connection.kill.join
      @thread_keep_clean.kill.join
      @tuple_space_servers = []
      send_packet
    end

    alias :terminate :finalize

    private

    # Start to run the provider.
    def keep_connection
      @thread_keep_connection = Thread.new do
        while true do
          send_packet
          sleep 3
        end
      end
    end

    # Send UDP packet.
    def send_packet
      socket = UDPSocket.open
      begin
        puts "sent UDP packet ..." if debug_mode?
        # send UDP packet
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
        #socket.send(dump, 0, '<broadcast>', @udp_port)
        socket.send(@remote_object, 0, Socket::INADDR_BROADCAST, @udp_port)
      rescue
        nil
      ensure
        socket.close
      end
    end

    # Keep clean.
    def keep_clean
      @thread_keep_clean = Thread.new do
        while true do
          clean
          sleep 1
        end
      end
    end

    # Delete dead or expired tuple space servers.
    def clean
      synchronize do
        delete = []
        # find dead or expired servers
        @tuple_space_servers.each do |ts_server, time|
          begin
            if ts_server.alive?
              if Time.now - time > @expiration_time
                delete << ts_server
              end
            end
          rescue
            delete << ts_server
          end
        end
        # delete target servers
        delete.each do |ts_server|
          @tuple_space_servers.delete(ts_server)
        end
      end
    end

  end

end
