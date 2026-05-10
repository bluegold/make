module TaskRunner
  class Normalizer
    def initialize(program)
      @program = program
      @expander = Expander.new(program.variables)
    end

    def normalize
      tasks = {}
      rules = []
      phony_targets = Set.new

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

      @program.rules.each do |rule|
        expanded_target = @expander.expand(rule.target_pattern).dup.freeze
        expanded_prereqs = rule.prerequisite_patterns.flat_map do |prereq|
          @expander.expand(prereq).split(/\s+/).reject(&:empty?).map { |name| name.dup.freeze }
        end

        rules << Rule.new(
          expanded_target,
          expanded_prereqs.freeze,
          rule.commands.map { |command| command.dup.freeze }.freeze,
          rule.source_line
        )
      end

      @program.phony_targets.each do |phony_target|
        expanded = @expander.expand(phony_target).dup.freeze
        phony_targets << expanded
      end

      tasks.each_value(&:freeze)
      rules.each(&:freeze)

      Level4Program.new(
        tasks.freeze,
        rules.freeze,
        @program.variables.transform_keys { |key| key.dup.freeze }.transform_values { |value| value.dup.freeze }.freeze,
        @program.first_target && @expander.expand(@program.first_target).dup.freeze,
        phony_targets.freeze
      )
    end
  end
end
