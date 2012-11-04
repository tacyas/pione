module Pione
  module Relay
    # RelaySocket is connection layer between PIONE client and PIONE relay.
    class RelaySocket < DRb::DRbSSLSocket
      # AuthError is an error for relay authentication failure.
      class AuthError < StandardError; end

      # ProxyError is raised when proxy server cannot start.
      class ProxyError < StandardError; end

      # BadMessage is an error for protocol violation.
      class BadMessage < Exception; end

      def self.parse_uri(uri)
        if uri =~ /^relay:\/\/(.*?)(:(\d+))?(\?(.*))?$/
          host = $1
          port = $3 ? $3.to_i : Global.relay_port
          option = $5
          return [host, port, option]
        else
          raise(DRb::DRbBadScheme, uri) unless uri =~ /^relay:/
          raise(DRb::DRbBadURI, 'can\'t parse uri:' + uri)
        end
      end

      # Opens the socket on pione-client.
      def self.open(uri, config)
        host, port, option = parse_uri(uri)
        host.untaint
        port.untaint

        # make tcp connection with SSL
        soc = TCPSocket.open(host, port)
        ssl_conf = DRb::DRbSSLSocket::SSLConfig.new(config)
        ssl_conf.setup_ssl_context
        ssl = ssl_conf.connect(soc)

        if Global.show_communication
          puts "you connected relay socket to %s" % uri
        end

        # auth like HTTP's digest method
        begin
          Timeout.timeout(Global.relay_client_auth_timeout_sec) do
            realm = ssl.gets.chomp
            uuid = ssl.gets.chomp
            account = Global.relay_account_db[realm] || (raise AuthError.new("unknown realm: %s" % realm))
            name = account.name
            digest = account.digest
            response = "%s:%s" % [name, Digest::SHA512.hexdigest("%s:%s" % [uuid, digest])]
            ssl.puts(response)
            unless ssl.read(3).chomp == "OK"
              raise AuthError.new("authentication failed")
            end
          end
        rescue AuthError => e
          raise e
        rescue Timeout::Error
          raise AuthError.new("authentication timeout")
        end

        if Global.show_communication
          puts "you succeeded relay authentication: %s" % uri
        end

        # create receiver socket
        ReceiverSocket.table["%s:%s" % [host, port]] = ssl
        Global.relay_receiver = DRb::DRbServer.new(
          "receiver://%s:%s" % [host, port],
          Global.relay_tuple_space_server
        )

        # create an instance
        return self.new(uri, ssl, ssl_conf, true)
      end

      # Opens relay server port for clients.
      # @api private
      def self.open_server(uri, config)
        uri = 'relay://:%s' % Global.relay_port unless uri
        host, port, option = parse_uri(uri)
        if host.size == 0
          host = getservername
          soc = open_server_inaddr_any(host, port)
        else
          soc = TCPServer.open(host, port)
        end
        port = soc.addr[1] if port == 0
        @uri = "relay://#{host}:#{port}"

        # prepare SSL
        ssl_conf = DRb::DRbSSLSocket::SSLConfig.new(config)
        ssl_conf.setup_certificate
        ssl_conf.setup_ssl_context

        # create an instance
        self.new(@uri, soc, ssl_conf, false)
      end

      def self.uri_option(uri, config)
        host, port, option = parse_uri(uri)
        return "relay://#{host}:#{port}", option
      end

      # Accepts clients on server side.
      # @api private
      def accept
        begin
          while true
            soc = @socket.accept
            break if (@acl ? @acl.allow_socket?(soc) : true)
            soc.close
          end

          ssl = @config.accept(soc)

          if Global.show_communication
            puts "someone connected to relay socket..."
          end

          # relay auth like HTTP's digest method
          ssl.puts(Global.relay_realm)
          uuid = Util.generate_uuid
          ssl.puts(uuid)
          if msg = ssl.gets
            name, digest = msg.chomp.split(":")
            unless Global.relay_client_db.auth(uuid, name, digest)
              raise AuthError.new(name)
            end
            ssl.puts "OK"

            if Global.show_communication
              puts "succeeded authentication for %s" % name
            end

            # setup transmitter_id
            transmitter_id = Util.generate_uuid
            TransmitterSocket.table[transmitter_id] = ssl

            # create servers
            create_transmitter_server(transmitter_id)
            create_proxy_server(transmitter_id)

            # create an object
            self.class.new(uri, ssl, @config, true)
          else
            raise BadMessage
          end
        rescue OpenSSL::SSL::SSLError
          warn("#{__FILE__}:#{__LINE__}: warning: #{$!.message} (#{$!.class})") if @config[:verbose]
          retry
        rescue AuthError, BadMessage => e
          if Global.show_communication
            puts "relay socket disconnected"
            puts "%s: %s" % [e.class, e.message]
            caller.each {|line| puts "    %s" % line}
          end
          soc.close
          retry
        end
      end

      # Creates a transmitter server with the relay socket.
      # @return [void]
      def create_transmitter_server(transmitter_id)
        server = DRb::DRbServer.new("transmitter://%s" % transmitter_id, nil)
        if Global.show_communication
          puts "relay created the transmitter: %s" % server.uri
        end
        return server
      end

      # Creates a proxy server for brokers in LAN.
      def create_proxy_server(transmitter_id)
        transmitter = DRb::DRbObject.new_with_uri("transmitter://%s" % transmitter_id)
        Global.relay_proxy_port_range.each do |port|
          begin
            uri = "druby://localhost:%s" % port
            server = DRb::DRbServer.new(uri, transmitter)
            if Global.show_communication
              puts "relay created the proxy: %s" % server.uri
            end
            return server
          rescue
            next
          end
        end
        raise ProxyError.new("You cannot start proxy server.")
      end
    end

    # install the protocol
    DRb::DRbProtocol.add_protocol(RelaySocket)
  end
end