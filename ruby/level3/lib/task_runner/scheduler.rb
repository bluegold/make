require "etc"

module TaskRunner
  class Scheduler
    def initialize(program, max_workers: nil)
      @program = program
      @resolver = Resolver.new(program.tasks)
      @expander = Expander.new(program.variables)
      @max_workers = max_workers
    end

    def run(target_name)
      ordered_tasks = @resolver.resolve(target_name)
      task_map = ordered_tasks.each_with_object({}) do |task, result|
        result[task.name] = task
      end

      raise UnknownTargetError, "Error: No targets found." if task_map.empty?

      reachable_order = ordered_tasks.map(&:name)
      reachable_set = reachable_order.to_set
      indegree = Hash.new(0)
      dependents = Hash.new { |hash, key| hash[key] = [] }

      task_map.each_value do |task|
        task.dependencies.each do |dependency|
          next unless reachable_set.include?(dependency)

          indegree[task.name] += 1
          dependents[dependency] << task.name
        end
      end

      ready = reachable_order.select { |name| indegree[name].zero? }
      completed = Set.new
      inflight = 0
      worker_count = [reachable_order.size, requested_workers].min
      worker_count = 1 if worker_count < 1
      result_port = Ractor::Port.new
      workers = Array.new(worker_count) do
        spawn_worker(result_port)
      end
      available_workers = (0...worker_count).to_a

      begin
        until completed.size == task_map.size
          progressed = false

          while ready.any? && available_workers.any?
            task_name = ready.shift
            task = task_map[task_name]
            worker_index = available_workers.shift

            if needs_update?(task.name, task.dependencies)
              workers[worker_index].send({ name: task_name, worker_index: worker_index })
              inflight += 1
            else
              complete_task(task_name, completed, indegree, dependents, ready)
              available_workers << worker_index
            end

            progressed = true
          end

          next if progressed

          break if inflight.zero?

          result = result_port.receive
          inflight -= 1

          if result[:ok]
            complete_task(result[:name], completed, indegree, dependents, ready)
            available_workers << result[:worker_index]
          else
            workers.each { |worker| worker.send(:stop) rescue nil }
            raise CommandError, result[:message]
          end
        end
      ensure
        workers.each { |worker| worker.send(:stop) rescue nil }
      end
    end

    private

    def requested_workers
      @max_workers || 4
    end

    def spawn_worker(result_port)
      Ractor.new(result_port, @program) do |results, program|
        expander = TaskRunner::Expander.new(program.variables)

        loop do
          message = Ractor.receive
          break if message == :stop

          task_name = message[:name]
          worker_index = message[:worker_index]

          task = program.tasks[task_name]
          begin
            extra_vars = {
              "$@" => task.name,
              "$<" => task.dependencies.first.to_s,
              "$^" => task.dependencies.join(" "),
            }

            task.commands.each do |command|
              expanded_command = expander.expand(command, extra_vars: extra_vars, allow_special: true)
              silent = expanded_command.start_with?("@")
              actual_command = silent ? expanded_command.delete_prefix("@").lstrip : expanded_command

              unless silent
                puts "Executing: #{actual_command}"
                $stdout.flush
              end

              success = system(actual_command)
              next if success

              status = $?.respond_to?(:exitstatus) ? $?.exitstatus : 1
              raise CommandError, "Error: Command '#{actual_command}' failed with exit code #{status}"
            end

            results.send({ name: task.name, worker_index: worker_index, ok: true })
          rescue Error => e
            results.send({ name: task.name, worker_index: worker_index, ok: false, message: e.message })
          rescue StandardError => e
            results.send({ name: task.name, worker_index: worker_index, ok: false, message: e.message })
          end
        end
      end
    end

    def complete_task(task_name, completed, indegree, dependents, ready)
      return if completed.include?(task_name)

      completed << task_name

      dependents[task_name].each do |dependent_name|
        indegree[dependent_name] -= 1
        ready << dependent_name if indegree[dependent_name].zero?
      end
    end

    def needs_update?(target, dependencies)
      return true unless File.exist?(target)

      target_mtime = File.mtime(target)
      dependencies.each do |dependency|
        next unless File.exist?(dependency)

        return true if File.mtime(dependency) > target_mtime
      end

      false
    end
  end
end
