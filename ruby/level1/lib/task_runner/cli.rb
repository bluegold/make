module TaskRunner
  class CLI
    def self.run(argv)
      taskfile = argv[0] || "Taskfile"
      target_name = argv[1]

      program = Parser.new.parse(taskfile)
      target_name ||= program.first_target

      raise UnknownTargetError, "Error: No targets found in '#{taskfile}'." if target_name.nil?

      Executor.new(program).run(target_name)
    rescue Error => e
      warn e.message
      exit 1
    end
  end
end
