module TaskRunner
  Task = Data.define(:name, :dependencies, :commands, :source_line)
  ParsedProgram = Data.define(:tasks, :variables, :first_target)
end
