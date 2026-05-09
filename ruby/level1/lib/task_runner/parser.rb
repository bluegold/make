module TaskRunner
  class Parser
    def parse(path)
      unless File.exist?(path)
        raise ParseError, "Error: File '#{path}' not found."
      end

      tasks = {}
      variables = {}
      first_target = nil
      current_task = nil

      File.foreach(path, chomp: true).with_index(1) do |raw_line, line_no|
        line = raw_line.rstrip

        next if line.empty?
        next if line.lstrip.start_with?("#")

        case line
        in /\A[ \t].*/
          if current_task
            command = line.strip
            current_task.commands << command unless command.empty?
          end
        in /\A[^:=\s]+\s*=\s*.*\z/
          match = line.match(/\A(?<name>[^:=\s]+)\s*=\s*(?<value>.*)\z/)
          variables[match[:name]] = match[:value]
          current_task = nil
        in /\A[^:]+\s*:\s*.*\z/
          match = line.match(/\A(?<target>[^:]+)\s*:\s*(?<deps>.*)\z/)
          target_name = match[:target].strip
          dependencies = match[:deps].split(/\s+/).reject(&:empty?)
          task = Task.new(target_name, dependencies, [], line_no)
          tasks[target_name] = task
          first_target ||= target_name
          current_task = task
        else
          raise ParseError, "Error: Unrecognized syntax on line #{line_no}."
        end
      end

      freeze_program(tasks, variables, first_target)
    end

    private

    def freeze_program(tasks, variables, first_target)
      tasks.each_value do |task|
        task.dependencies.freeze
        task.commands.freeze
        task.freeze
      end

      ParsedProgram.new(tasks.freeze, variables.freeze, first_target)
    end
  end
end
