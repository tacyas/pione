module Pione::Model

  # DataExpr is a class for data name expressions of rule input and output.
  class DataExpr < PioneModelObject

    # separator symbol for all modifier
    SEPARATOR = ':'

    # DataExpr::Compiler is a regexp compiler for data expression.
    module Compiler
      TABLE = {}

      # Define a string matcher.
      def self.define_matcher(matcher, replace)
        TABLE[Regexp.escape(matcher)] = replace
      end

      # Asterisk symbol is multi-characters matcher(empty string is matched).
      define_matcher('*', '(.*)')

      # Question symbol is single character matcher(empty string is not matched).
      define_matcher('?', '(.)')

      # Compile data name into regular expression.
      def compile(name)
        return name unless name.kind_of?(String)

        s = "^#{Regexp.escape(name)}$"
        TABLE.keys.each {|key| s.gsub!(key, TABLE)}
        s.gsub!(/\\\[(!|\\\^)?(.*)\\\]/){"[#{'^' if $1}#{$2.gsub('\-','-')}]"}
        s.gsub!(/\\{(.*)\\}/){"(#{$1.split(',').join('|')})"}
        Regexp.new(s)
      end
      module_function :compile
    end

    # This module implements DataExpr singleton methods.
    module SingletonMethod
      # Create a name expression.
      def [](name)
        new(name)
      end

      # Create a name expression with 'each' modifier.
      def each(name)
        new(name, :each)
      end

      # Create a name expression with 'all' modifier.
      def all(name)
        new(name, :all)
      end

      # Create a data name for stdout ouput.
      def stdout(name)
        new(name, :each, :stdout)
      end

      # Create a data name for stderr output.
      def stderr(name)
        new(name, :each, :stderr)
      end

      # Return convertion prcedure for enumerable.
      def to_proc
        Proc.new{|name| name.kind_of?(self) ? name : self.new(name)}
      end

      def attribution(name, &b)
        Attribution.new(name, &b)
      end
    end

    extend SingletonMethod

    attr_reader :name
    attr_reader :modifier
    attr_reader :mode
    attr_reader :exceptions

    # Create a data expression.
    # [+name+] data expression name
    # [+modifier+] all / each
    # [+mode+] nil / stdout / stderr
    def initialize(name, modifier = :each, mode = nil, exceptions = [])
      unless name.kind_of? String or name.kind_of? Regexp
        raise ArgumentError.new(name)
      end

      @name = name
      @modifier = modifier
      @mode = mode
      @exceptions = exceptions
    end

    def pione_model_type
      TypeDataExpr
    end

    # Set it each modifier.
    def each
      return self.class.new(@name, :each, @mode, @exceptions)
    end

    # Set it all modifier.
    def all
      return self.class.new(@name, :all, @mode, @exceptions)
    end

    # Set it stdout mode.
    def stdout
      return self.class.new(@name, @modifier, :stdout, @exceptions)
    end

    # Set it stderr mode.
    def stderr
      return self.class.new(@name, @modifier, :stderr, @exceptions)
    end

    # Evaluates the data expression.
    def eval(vtable)
      exceptions = @exceptions.map {|exc| exc.eval(vtable)}
      self.class.new(vtable.expand(name), @modifier, @mode, exceptions)
    end

    def include_variable?
      VariableTable.check_include_variable(@name)
    end

    def task_id_string
      "DataExpr<#{@name},#{@modifier},[%s]>" % [
        @exceptions.map{|exc| exc.task_id_string}.join(",")
      ]
    end

    def textize
      "data_expr(\"#{@name}\",:#{@modifier},[%s]>" % [
        @exceptions.map{|exc| exc.textize}.join(",")
      ]
    end

    # Return true if the name has 'all' modifier.
    def all?
      @modifier == :all
    end

    # Return true if the name has 'exist' modifier.
    def each?
      @modifier == :each
    end

    # Return true if the data content is in stdout.
    def stdout?
      @mode == :stdout
    end

    # Return true if the data content is in stderr.
    def stderr?
      @mode == :stderr
    end

    # Set a exception and return self.
    # def except(*names)
    #   @exceptions += names.map do |name|
    #     name.kind_of?(DataExpr) ? name : DataExpr.new(name)
    #   end
    #   return self
    # end
    def except(name)
      exceptions =
        @exceptions.clone + [name.kind_of?(DataExpr) ? name : DataExpr.new(name)]
      return self.class.new(@name, @modifier, @mode, exceptions)
    end

    # Return matched data if the name is matched with the expression.
    def match(other)
      # check exceptions
      return false if match_exceptions(other)
      # match test
      md = nil
      @name.split(SEPARATOR).each do |name|
        break if md = compile_to_regexp(name).match(other)
      end
      return md
    end

    # Select from name list matched with the expression.
    def select(*names)
      names.flatten.select {|name| match(name) }
    end

    # Generate concrete name string by arguments.
    # usage: DataExpr["test-*.rb"].generate(1) # => "test-1.rb"
    def generate(*args)
      name = @name.clone
      while name =~ /(\*|\?)/ and not(args.empty?)
        val = args.shift.to_s
        name.sub!(/(\*|\?)/){$1 == "*" ? val : val[0]}
      end
      return name
    end

    # Return true if name, modifier, mode, and exceptions are the same.
    def ==(other)
      return false unless other.kind_of?(self.class)
      return false unless @name == other.name
      return false unless @modifier == other.modifier
      return false unless @mode == other.mode
      return false unless @exceptions.sort == other.exceptions.sort
      return true
    end

    alias eql? ==

    # Return hash value.
    def hash
      [@name, @modifier, @mode, @exceptions].join("\000").hash
    end

    # Same as Regexp#=~ but return 0 if it matched.
    def =~(other)
      match(other) ? 0 : nil
    end

    # Pattern match.
    def ===(other)
      match(other) ? true : false
    end

    private

    # :nodoc:
    def compile_to_regexp(name)
      Compiler.compile(name)
    end

    # Return true if the name matchs exceptions.
    def match_exceptions(name)
      not(@exceptions.select{|ex| ex.match(name)}.empty?)
    end
  end

  TypeDataExpr.instance_eval do
    define_pione_method("==", [TypeDataExpr], TypeBoolean) do |rec, other|
      PioneBoolean.new(rec == other)
    end

    define_pione_method("!=", [TypeDataExpr], TypeBoolean) do |rec, other|
      PioneBoolean.not(rec.call_pione_method("==", other))
    end

    define_pione_method("all", [], TypeDataExpr) do |rec|
      rec.all
    end

    define_pione_method("each", [], TypeDataExpr) do |rec|
      rec.each
    end

    define_pione_method("except", [TypeDataExpr], TypeDataExpr) do |rec, target|
      rec.except(target)
    end

    define_pione_method("stdout", [], TypeDataExpr) do |rec|
      rec.stdout
    end

    define_pione_method("stderr", [], TypeDataExpr) do |rec|
      rec.stderr
    end
  end
end
