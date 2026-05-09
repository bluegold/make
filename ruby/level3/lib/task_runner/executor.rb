module TaskRunner
  class Executor
    def initialize(program)
      @program = program
    end

    def run(target_name)
      Scheduler.new(@program).run(target_name)
    end
  end
end
