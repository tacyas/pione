module Pione::Model
  class PioneString < PioneModelObject
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def pione_model_type
      TypeString
    end

    def to_ruby
      return @value
    end

    def ==(other)
      return false unless other.kind_of?(self.class)
      @value == other.value
    end

    alias :eql? :==

    def hash
      @value.hash
    end
  end

  TypeString.instance_eval do
    define_pione_method("==", [TypeString], TypeBoolean) do |rec, other|
      PioneBoolean.new(rec.value == other.value)
    end

    define_pione_method("!=", [TypeString], TypeBoolean) do |rec, other|
      PioneBoolean.not(rec.call_pione_method("==", other))
    end

    define_pione_method("+", [TypeString], TypeString) do |rec, other|
      PioneString.new(rec.value + other.value)
    end

    define_pione_method("as_string", [], TypeString) do |rec|
      rec
    end

    define_pione_method("as_int", [], TypeInteger) do |rec|
      PioneInteger.new(rec.value.to_i)
    end

    define_pione_method("as_float", [], PioneFloat) do |rec|
      PioneFloat.new(rec.value.to_f)
    end

    define_pione_method("length", [], TypeInteger) do |rec|
      PioneInteger.new(rec.value.size)
    end

    define_pione_method("include?", [TypeString], TypeBoolean) do |rec, str|
      PioneBoolean.new(rec.value.include?(str.value))
    end

    define_pione_method("substring",
                        [TypeInteger, TypeInteger],
                        TypeString) do |rec, nth, len|
      PioneString.new(rec.value[nth.value, len.value])
    end
  end
end