module TaskRunner
  class Normalizer
    def initialize(program)
      @program = program
      @expander = Expander.new(program.variables)
    end

    def normalize
      tasks = {}
      variables = @program.variables.each_with_object({}) do |(key, value), result|
        result[key.dup.freeze] = value.dup.freeze
      end

      @program.tasks.each_value do |task|
        expanded_name = @expander.expand(task.name).dup.freeze
        expanded_dependencies = task.dependencies.flat_map do |dependency|
          @expander.expand(dependency).split(/\s+/).reject(&:empty?).map { |name| name.dup.freeze }
        end

        tasks[expanded_name] = Task.new(
          expanded_name,
          expanded_dependencies.freeze,
          task.commands.map { |command| command.dup.freeze }.freeze,
          task.source_line
        )
      end

      tasks.each_value(&:freeze)

      ParsedProgram.new(
        tasks.freeze,
        variables.freeze,
        @program.first_target && @expander.expand(@program.first_target).dup.freeze
      )
    end
  end
end
