module TaskRunner
  class Expander
    SPECIAL_VARS = {
      "$@" => :target,
      "$<" => :first_dependency,
      "$^" => :all_dependencies,
    }.freeze

    def initialize(variables)
      @variables = variables
    end

    def expand(text, extra_vars: {}, allow_special: false, expanding: Set.new)
      return text if text.nil? || text.empty?

      expanded = expand_special_vars(text, extra_vars, allow_special)
      expanded.gsub(/\$\(([^)]+)\)/) do
        var_name = Regexp.last_match(1)
        expand_variable(var_name, extra_vars, allow_special, expanding)
      end
    end

    private

    def expand_special_vars(text, extra_vars, allow_special)
      text.gsub(/\$([@<^])/) do |match|
        key = "$#{Regexp.last_match(1)}"
        next extra_vars[key] if extra_vars.key?(key)

        if allow_special
          match
        else
          raise UnsupportedSpecialVariableError, "Error: Special variable '#{key}' is not supported in level2."
        end
      end
    end

    def expand_variable(var_name, extra_vars, allow_special, expanding)
      if expanding.include?(var_name)
        cycle = (expanding.to_a + [var_name]).join(" -> ")
        raise CircularVariableReferenceError, "Circular variable reference detected"
      end

      raw_value = extra_vars[var_name]
      raw_value = ENV[var_name] if raw_value.nil? && ENV.key?(var_name)
      raw_value = @variables[var_name] if raw_value.nil? && @variables.key?(var_name)
      raw_value = "" if raw_value.nil?

      expanding.add(var_name)
      result = expand(raw_value, extra_vars: extra_vars, allow_special: allow_special, expanding: expanding)
      expanding.delete(var_name)
      result
    end
  end
end
