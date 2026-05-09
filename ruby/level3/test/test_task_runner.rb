require "minitest/autorun"
require "open3"
require "tmpdir"

require_relative "../lib/task_runner"

class TaskRunnerLevel3Test < Minitest::Test
  def test_auto_variables_expand
    output, status = run_runner(sample_path("03_advanced/02_auto_vars.txt"), "final_report.pdf")

    assert status.success?
    assert_includes output, "ターゲット: final_report.pdf"
    assert_includes output, "すべての依存: intro.md body.md conclusion.md"
    assert_includes output, "最初の依存: intro.md"
  end

  def test_environment_overrides_variables
    output, status = run_runner(
      sample_path("03_advanced/04_env_override.txt"),
      "welcome",
      env: { "TASK_RUNNER_TEST_USER" => "codex" }
    )

    assert status.success?
    assert_includes output, "Welcome, codex!"
  end

  def test_timestamp_skip
    Dir.mktmpdir do |dir|
      taskfile = File.join(dir, "Taskfile")
      input = File.join(dir, "input.data")
      output_file = File.join(dir, "output.data")

      File.write(taskfile, <<~TASKFILE)
        output.data: input.data
        	echo "Processing input.data..."
        	cat input.data > output.data
      TASKFILE
      File.write(input, "hello\n")

      first_output, first_status = run_runner(taskfile, "output.data")
      assert first_status.success?
      assert_includes first_output, 'Executing: echo "Processing input.data..."'

      second_output, second_status = run_runner(taskfile, "output.data")
      assert second_status.success?
      refute_includes second_output, 'Executing: echo "Processing input.data..."'
      assert File.exist?(output_file)
    end
  end

  def test_parallel_execution_finishes_quickly
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output, status = run_runner(sample_path("03_advanced/03_parallel.txt"), "all")
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    assert status.success?
    assert_includes output, "Task A starting..."
    assert_includes output, "Task B starting..."
    assert duration < 3.0
  end

  def test_special_variables_are_supported
    Dir.mktmpdir do |dir|
      taskfile = File.join(dir, "Taskfile")

      File.write(taskfile, <<~TASKFILE)
        output.bin:
        	echo "Generating $@"
        	touch $@
      TASKFILE

      output, status = run_runner(taskfile, "output.bin")

      assert status.success?
      assert_includes output, 'Executing: echo "Generating output.bin"'
    end
  end

  private

  def run_runner(taskfile, target, env: {})
    sample_dir = File.dirname(taskfile)
    sample_file = File.basename(taskfile)
    runner = File.expand_path("../../runner", __dir__)
    cmd = [runner, "level3", sample_file, target]
    Open3.capture2e(env, *cmd, chdir: sample_dir)
  end

  def sample_path(relative)
    File.expand_path("../../../samples/#{relative}", __dir__)
  end
end
