module TaskRunner
  class Resolver
    def initialize(tasks)
      @tasks = tasks
    end

    def resolve(target_name)
      task = @tasks[target_name]
      raise UnknownTargetError, "Error: Unknown target '#{target_name}'." unless task

      order = []
      visited = Set.new
      visiting = Set.new

      visit(target_name, visited, visiting, order)
      order
    end

    private

    def visit(target_name, visited, visiting, order)
      return if visited.include?(target_name)

      if visiting.include?(target_name)
        raise CircularDependencyError, "Circular dependency detected"
      end

      task = @tasks[target_name]
      return unless task

      visiting << target_name
      task.dependencies.each do |dependency|
        visit(dependency, visited, visiting, order)
      end
      visiting.delete(target_name)
      visited << target_name
      order << task
    end
  end
end
