module TaskRunner
  class Executor
    def initialize(program)
      @program = program
      @resolver = Resolver.new(program.tasks)
      @expander = Expander.new(program.variables)
    end

    def run(target_name)
      @resolver.resolve(target_name).each do |task|
        task.commands.each do |command|
          run_command(task, command)
        end
      end
    end

    private

    def run_command(task, command)
      expanded_command = @expander.expand(command)
      silent = expanded_command.start_with?("@")
      actual_command = silent ? expanded_command.delete_prefix("@").lstrip : expanded_command

      unless silent
        puts "Executing: #{actual_command}"
        $stdout.flush
      end

      success = system(actual_command)
      return if success

      status = $?.respond_to?(:exitstatus) ? $?.exitstatus : 1
      raise CommandError, "Error: Command '#{actual_command}' failed with exit code #{status}"
    end
  end
end
