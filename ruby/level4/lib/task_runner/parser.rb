module TaskRunner
  class Parser
    def parse(path)
      unless File.exist?(path)
        raise ParseError, "Error: File '#{path}' not found."
      end

      tasks = {}
      rules = []
      variables = {}
      phony_targets = Set.new
      first_target = nil
      current_entry = nil
      current_kind = nil

      File.foreach(path, chomp: true).with_index(1) do |raw_line, line_no|
        line = raw_line.rstrip

        next if line.empty?
        next if line.lstrip.start_with?("#")

        case line
        in /\A[ \t].*/
          command = line.strip
          next if command.empty? || current_entry.nil?

          current_entry.commands << command
        in /\A\.PHONY\s*:\s*.*\z/
          match = line.match(/\A\.PHONY\s*:\s*(?<targets>.*)\z/)
          phony_targets.merge(match[:targets].split(/\s+/).reject(&:empty?))
          current_entry = nil
          current_kind = nil
        in /\A[^:=\s]+\s*=\s*.*\z/
          match = line.match(/\A(?<name>[^:=\s]+)\s*=\s*(?<value>.*)\z/)
          variables[match[:name]] = match[:value]
          current_entry = nil
          current_kind = nil
        in /\A[^:]+\s*:\s*.*\z/
          match = line.match(/\A(?<target>[^:]+)\s*:\s*(?<deps>.*)\z/)
          target = match[:target].strip
          dependencies = match[:deps].split(/\s+/).reject(&:empty?)

          if target.include?('%')
            rule = Rule.new(target, dependencies, [], line_no)
            rules << rule
            current_entry = rule
            current_kind = :rule
          else
            task = Task.new(target, dependencies, [], line_no)
            tasks[target] = task
            first_target ||= target
            current_entry = task
            current_kind = :task
          end
        else
          raise ParseError, "Error: Unrecognized syntax on line #{line_no}."
        end
      end

      Level4Program.new(tasks, rules, variables, first_target, phony_targets)
    end
  end
end
