module Pione
  module Command
    module ProcessClient
      def self.default_task_worker_size
        Pione.get_core_number - 1
      end

      def initialize
        super()
        @input_dir = nil
        @base_uri = ::URI.parse("local:./output/")
        @log_path = "log.txt"
        @stream = false
        @params = Parameters.empty
        @dry_run = false
        @resource = self.class.default_task_worker_size
        @worker_threads = []
      end

      def included(com)
        com.define_option('-i dir', '--input-dir=dir') do |dir|
          @input_dir = dir
        end

        com.define_option('-b uri', '--base-uri=uri', 'base uri') do |uri|
          base_uri = ::URI.parse(uri)
          @base_uri = base_uri.to_s
        end

        com.define_option('-l path', '--log=path', 'log path') do |path|
          @log_path = path
        end

        com.define_option('-s', '--stream') do
          @stream = true
        end

        com.define_option('-r n', '--resource=n') do |n|
          @resource = n.to_i
          unless @resource > 0
            puts "invalid resource size: %s" % @resource
            abort
          end
        end

        com.define_option('--params="{Var:1,...}"') do |str|
          @params = Transformer.new.apply(Parser.new.parameters.parse(str))
        end

        com.define_option('--dry-run') do |b|
          @dry_run = true
        end
      end

      def run
        read_process_document
        setup_tuple_space_server
        start_agents
        prepare_tuple_space_provider
        start_workers
        Agent[:process_manager].start(@tuple_space_server, @document, @params)
      end

      private

      def read_process_document
        # process definition document is not found.
        if ARGF.filename == "-"
          puts "There are no process definition documents."
          abort
        end

        # get script dirname
        @dir = File.dirname(File.expand_path(__FILE__))

        # base uri
        if @base_uri.scheme == "local"
          FileUtils.makedirs(@base_uri.path)
          @base_uri = @base_uri.absolute
        end
        @base_uri = @base_uri.to_s

        provider = TupleSpace::TupleSpaceProvider.instance
        provider.add(@tuple_space_server)

        # read process document
        begin
          @doc = Document.parse(ARGF.read)
        rescue Pione::Parser::ParserError => e
          abort("Pione syntax error: " + e.message)
        rescue Pione::Model::PioneModelTypeError, Pione::Model::VariableBindingError => e
          abort("Pione model error: " + e.message)
        end
      end

      def setup_tuple_space_server
        # make drb server and it's connection
        @tuple_space_server = TupleSpaceServer.new(
          task_worker_resource: @resource,
          base_uri: @base_uri
        )
        front.tuple_space_server = @tuple_space_server

        @tuple_space_server.write(
          Tuple[:process_info].new('standalone', 'Standalone')
        )
        @tuple_space_server.write(Tuple[:dry_run].new(@dry_run))
      end

      def start_agents
        # logger
        Agent[:logger].start(@tuple_space_server, File.open(@log_path, "w+"))

        # rule provider
        @rule_loader = Agent[:rule_provider].start(@tuple_space_server)
        @rule_loader.read_document(@doc)
        @rule_loader.wait_till(:request_waiting)

        # input generators
        generator_method = @stream ? :start_by_stream : :start_by_dir
        gen = Agent[:input_generator].send(
          generator_method, @tuple_space_server, @input_dir
        )
        sleep 0.1 while not(gen.counter > 0)
      end

      def prepare_tuple_space_provider
        @provider = Pione::TupleSpaceProvider.instance
        @provider.add($tuple_space_server)
      end

      def start_workers
        @resource.times {@worker_threads << Agent[:task_worker].spawn(front, Pione.generate_uuid)}
      end
    end
  end
end
