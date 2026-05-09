require "minitest/autorun"
require "tempfile"

require_relative "../lib/task_runner"

class TaskRunnerParserTest < Minitest::Test
  def test_parse_records_tasks_and_first_target
    Tempfile.create(["taskfile", ".txt"]) do |file|
      file.write <<~TASKFILE
        build: prep
        	echo "build"

        prep:
        	echo "prep"
      TASKFILE
      file.flush

      program = TaskRunner::Parser.new.parse(file.path)

      assert_equal "build", program.first_target
      assert_equal ["prep"], program.tasks["build"].dependencies
      assert_equal ["echo \"build\""], program.tasks["build"].commands
    end
  end

  def test_resolver_returns_dependencies_before_target
    program = TaskRunner::Parser.new.parse(sample_path("01_basic/diamond_dependency.txt"))
    order = TaskRunner::Resolver.new(program.tasks).resolve("all").map(&:name)

    assert_equal %w[init build test deploy all], order
  end

  private

  def sample_path(relative)
    File.expand_path("../../../samples/#{relative}", __dir__)
  end
end
