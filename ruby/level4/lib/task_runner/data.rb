module TaskRunner
  Rule = Data.define(:target_pattern, :prerequisite_patterns, :commands, :source_line)
  RuleMatch = Data.define(:rule, :stem, :specificity)
  Level4Program = Data.define(:tasks, :rules, :variables, :first_target, :phony_targets)
end
