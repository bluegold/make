require "minitest/autorun"
require "open3"
require "tmpdir"

require_relative "../lib/task_runner"

class TaskRunnerLevel4Test < Minitest::Test
  def test_pattern_rule_builds_source_targets
    output, status = run_runner(sample_path("04_implicit/01_pattern_build.txt"), "app")

    assert status.success?
    assert_includes output, "Compiling main.c -> main.o"
    assert_includes output, "Compiling util.c -> util.o"
    assert_includes output, "Linking app"
  end

  def test_rule_priority_prefers_explicit_rule
    output, status = run_runner(sample_path("04_implicit/02_rule_priority.txt"), "app")

    assert status.success?
    assert_includes output, "Explicit compile main.c -> main.o"
    assert_includes output, "Generic compile util.c -> util.o"
  end

  def test_phony_runs_even_if_named_like_file
    output, status = run_runner(sample_path("04_implicit/03_phony.txt"), "clean")

    assert status.success?
    assert_includes output, "Cleaning generated files"
  end

  def test_specific_pattern_is_preferred
    output, status = run_runner(sample_path("04_implicit/04_specificity.txt"), "app")

    assert status.success?
    assert_includes output, "Specific compile src/main.c -> src/main.o"
    assert_includes output, "Generic compile lib.c -> lib.o"
  end

  def test_rule_chain_resolves_transitively
    output, status = run_runner(sample_path("04_implicit/05_rule_chain.txt"), "app")

    assert status.success?
    assert_includes output, "Generating app.c from app.src"
    assert_includes output, "Compiling app.c -> app.o"
    assert_includes output, "Linking app"
  end

  def test_missing_rule_fails
    output, status = run_runner(sample_path("04_implicit/06_missing_rule_error.txt"), "app")

    refute status.success?
    assert_includes output, "No rule to make target 'missing.o'"
  end

  private

  def run_runner(taskfile, target)
    sample_dir = File.dirname(taskfile)
    sample_file = File.basename(taskfile)
    runner = File.expand_path("../../runner", __dir__)
    cmd = [runner, "level4", sample_file, target]
    Open3.capture2e(*cmd, chdir: sample_dir)
  end

  def sample_path(relative)
    File.expand_path("../../../samples/#{relative}", __dir__)
  end
end
