module TaskRunner
  class Executor
    def initialize(program)
      @program = program
      @resolver = RuleResolver.new(
        tasks: program.tasks,
        rules: program.rules,
        phony_targets: program.phony_targets
      )
    end

    def run(target_name)
      resolved_tasks = @resolver.resolve(target_name)
      runtime_program = Level4Program.new(
        resolved_tasks,
        [],
        @program.variables,
        @program.first_target,
        @program.phony_targets
      )

      Scheduler.new(runtime_program, max_workers: 1, phony_targets: @program.phony_targets).run(target_name)
    end
  end
end
