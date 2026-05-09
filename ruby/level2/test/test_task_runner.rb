require "minitest/autorun"
require "tempfile"
require "open3"

require_relative "../lib/task_runner"

class TaskRunnerLevel2Test < Minitest::Test
  def test_recursive_variable_expansion
    output, status = run_runner(sample_path("02_variables/02_recursive_vars.txt"), "build")

    assert status.success?
    assert_includes output, 'Executing: mkdir -p ./bin'
    assert_includes output, 'Executing: touch ./bin/myapp'
    assert_includes output, 'Executing: echo "Built ./bin/myapp"'
  end

  def test_late_binding_uses_final_value
    output, status = run_runner(sample_path("02_variables/03_late_binding.txt"), "print_vars")

    assert status.success?
    assert_includes output, 'Executing: echo "A is final_value"'
    assert_includes output, 'A is final_value'
  end

  def test_variable_loop_fails
    output, status = run_runner(sample_path("02_variables/05_var_loop_error.txt"), "loop_test")

    refute status.success?
    assert_includes output, "Circular variable reference detected"
  end

  def test_special_variables_are_rejected_in_level2
    output, status = run_runner(sample_path("02_variables/04_special_vars_error.txt"), "output.txt")

    refute status.success?
    assert_includes output, "Special variable '$@' is not supported in level2."
  end

  def test_variable_dependencies_expand_into_multiple_targets
    output, status = run_runner(sample_path("02_variables/06_var_dependency.txt"), "all")

    assert status.success?
    assert_includes output, "init"
    assert_includes output, "setup"
    assert_includes output, "prepare"
    assert_includes output, 'Executing: echo "build"'
    assert_includes output, "build"
  end

  private

  def run_runner(taskfile, target)
    sample_dir = File.dirname(taskfile)
    sample_file = File.basename(taskfile)
    runner = File.expand_path("../../runner", __dir__)
    cmd = [runner, "level2", sample_file, target]
    Open3.capture2e(*cmd, chdir: sample_dir)
  end

  def sample_path(relative)
    File.expand_path("../../../samples/#{relative}", __dir__)
  end
end
