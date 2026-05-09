module TaskRunner
  class Executor
    def initialize(program)
      @program = program
      @resolver = Resolver.new(program.tasks)
    end

    def run(target_name)
      @resolver.resolve(target_name).each do |task|
        task.commands.each do |command|
          run_command(command)
        end
      end
    end

    private

    def run_command(command)
      silent = command.start_with?("@")
      actual_command = silent ? command.delete_prefix("@").lstrip : command

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
