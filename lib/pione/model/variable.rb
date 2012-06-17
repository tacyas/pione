module Pione::Model
  # Variable represent variable name objects. A variable object can evaluates
  # its value with the variable table.
  class Variable < PioneModelObject
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def pione_model_type
      TypeAny
    end

    # Evaluates self variable name in the table and returns it.
    def eval(vtable=VariableTable.new)
      val = vtable.get(self)
      if val.nil?
        raise UnboundVariableError.new(self)
      end
      return val
    end

    # Return true if other is a variable object which name is same as myself.
    def ==(other)
      other.kind_of?(self.class) && @name == other.name
    end

    alias :eql? :==

    # Returns hash value.
    def hash
      @name.hash
    end
  end
end
