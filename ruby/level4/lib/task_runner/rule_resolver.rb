module TaskRunner
  class RuleResolver
    def initialize(tasks:, rules:, phony_targets:)
      @tasks = tasks
      @rules = rules
      @phony_targets = phony_targets
    end

    def resolve(target_name)
      resolved = {}
      visiting = Set.new
      resolve_target(target_name, resolved, visiting)
      resolved
    end

    private

    def resolve_target(target_name, resolved, visiting)
      return if resolved.key?(target_name)

      if visiting.include?(target_name)
        raise CircularDependencyError, "Circular dependency detected"
      end

      visiting.add(target_name)
      task = build_task(target_name)

      if task.nil?
        if File.exist?(target_name)
          task = Task.new(target_name, [], [], nil)
        else
          raise UnknownTargetError, "Error: No rule to make target '#{target_name}'."
        end
      end

      task.dependencies.each do |dependency|
        resolve_target(dependency, resolved, visiting)
      end

      visiting.delete(target_name)
      resolved[target_name] = task
    end

    def build_task(target_name)
      return @tasks[target_name] if @tasks.key?(target_name)

      match = best_rule_match(target_name)
      return nil if match.nil?

      rule = match.rule
      deps = rule.prerequisite_patterns.flat_map do |pattern|
        expand_pattern(pattern, match.stem).split(/\s+/).reject(&:empty?)
      end

      Task.new(
        target_name,
        deps,
        rule.commands.dup,
        rule.source_line
      )
    end

    def best_rule_match(target_name)
      matches = @rules.filter_map do |rule|
        stem = match_stem(rule.target_pattern, target_name)
        next if stem.nil?

        specificity = rule.target_pattern.delete('%').length
        RuleMatch.new(rule, stem, specificity)
      end

      matches.max_by { |match| [match.specificity, match.rule.target_pattern.length] }
    end

    def match_stem(pattern, target_name)
      return "" if pattern == target_name

      unless pattern.include?('%')
        return pattern == target_name ? "" : nil
      end

      prefix, suffix = pattern.split('%', 2)
      regex = /\A#{Regexp.escape(prefix)}(.+)#{Regexp.escape(suffix)}\z/
      match = target_name.match(regex)
      match && match[1]
    end

    def expand_pattern(pattern, stem)
      pattern.gsub('%', stem)
    end
  end
end
