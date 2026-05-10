require "minitest/autorun"
require "fileutils"
require "tmpdir"

require_relative "../lib/task_runner"

class TaskRunnerLevel4UnitTest < Minitest::Test
  def test_parser_recognizes_pattern_rules_and_phony_targets
    Dir.mktmpdir do |dir|
      taskfile = File.join(dir, "Taskfile")
      File.write(taskfile, <<~TASKFILE)
        NAME = app

        .PHONY: clean

        $(NAME): main.o
        	echo "link"

        %.o: %.c
        	echo "compile"
      TASKFILE

      program = TaskRunner::Parser.new.parse(taskfile)

      assert_equal "$(NAME)", program.first_target
      assert_equal ["$(NAME)"], program.tasks.keys
      assert_equal 1, program.rules.size
      assert_includes program.phony_targets, "clean"
    end
  end

  def test_normalizer_expands_targets_rules_and_phony_entries
    program = TaskRunner::Level4Program.new(
      {
        "$(NAME)" => TaskRunner::Task.new("$(NAME)", ["$(DEPS)"], ["echo link"], 4)
      },
      [
        TaskRunner::Rule.new("$(OBJ_PATTERN)", ["$(SRC_PATTERN)"], ["echo compile"], 6)
      ],
      {
        "NAME" => "app",
        "DEPS" => "main.o util.o",
        "OBJ_PATTERN" => "%.o",
        "SRC_PATTERN" => "%.c",
        "PHONY_TARGET" => "clean"
      },
      "$(NAME)",
      Set["$(PHONY_TARGET)"]
    )

    normalized = TaskRunner::Normalizer.new(program).normalize

    assert_equal "app", normalized.first_target
    assert_equal ["main.o", "util.o"], normalized.tasks["app"].dependencies
    assert_equal "%.o", normalized.rules.first.target_pattern
    assert_equal ["%.c"], normalized.rules.first.prerequisite_patterns
    assert_equal Set["clean"], normalized.phony_targets
  end

  def test_rule_resolver_prefers_explicit_tasks_and_uses_pattern_rules_for_missing_targets
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("main.c", "")
        File.write("util.c", "")

        tasks = {
          "main.o" => TaskRunner::Task.new("main.o", ["main.c"], ["echo explicit main"], 2),
          "app" => TaskRunner::Task.new("app", ["main.o", "util.o"], ["echo link"], 1)
        }
        rules = [
          TaskRunner::Rule.new("%.o", ["%.c"], ["echo generic"], 3)
        ]

        resolved = TaskRunner::RuleResolver.new(
          tasks: tasks,
          rules: rules,
          phony_targets: Set.new
        ).resolve("app")

        assert_equal ["main.c", "main.o", "util.c", "util.o", "app"], resolved.keys
        assert_equal ["main.c"], resolved["main.o"].dependencies
        assert_equal ["util.c"], resolved["util.o"].dependencies
      end
    end
  end

  def test_rule_resolver_prefers_more_specific_pattern_rules
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("src")
        File.write("src/main.c", "")
        File.write("lib.c", "")

        tasks = {
          "app" => TaskRunner::Task.new("app", ["src/main.o", "lib.o"], ["echo link"], 1)
        }
        rules = [
          TaskRunner::Rule.new("%.o", ["%.c"], ["echo generic"], 3),
          TaskRunner::Rule.new("src/%.o", ["src/%.c"], ["echo specific"], 4)
        ]

        resolved = TaskRunner::RuleResolver.new(
          tasks: tasks,
          rules: rules,
          phony_targets: Set.new
        ).resolve("app")

        assert_equal "echo specific", resolved["src/main.o"].commands.first
        assert_equal "echo generic", resolved["lib.o"].commands.first
        assert_equal ["src/main.c"], resolved["src/main.o"].dependencies
        assert_equal ["lib.c"], resolved["lib.o"].dependencies
      end
    end
  end

  def test_rule_resolver_resolves_rule_chains_transitively
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("app.src", "")

        tasks = {
          "app" => TaskRunner::Task.new("app", ["app.o"], ["echo link"], 1)
        }
        rules = [
          TaskRunner::Rule.new("%.c", ["%.src"], ["echo generate source"], 3),
          TaskRunner::Rule.new("%.o", ["%.c"], ["echo compile"], 4)
        ]

        resolved = TaskRunner::RuleResolver.new(
          tasks: tasks,
          rules: rules,
          phony_targets: Set.new
        ).resolve("app")

        assert_equal ["app.src", "app.c", "app.o", "app"], resolved.keys
        assert_equal ["app.src"], resolved["app.c"].dependencies
        assert_equal ["app.c"], resolved["app.o"].dependencies
      end
    end
  end

  def test_rule_resolver_raises_when_no_rule_exists
    error = assert_raises(TaskRunner::UnknownTargetError) do
      TaskRunner::RuleResolver.new(
        tasks: {},
        rules: [],
        phony_targets: Set.new
      ).resolve("missing")
    end

    assert_equal "Error: No rule to make target 'missing'.", error.message
  end

  def test_rule_resolver_detects_circular_dependencies
    tasks = {
      "app" => TaskRunner::Task.new("app", ["build"], ["echo app"], 1),
      "build" => TaskRunner::Task.new("build", ["app"], ["echo build"], 2)
    }

    error = assert_raises(TaskRunner::CircularDependencyError) do
      TaskRunner::RuleResolver.new(
        tasks: tasks,
        rules: [],
        phony_targets: Set.new
      ).resolve("app")
    end

    assert_equal "Circular dependency detected", error.message
  end

  def test_rule_resolver_treats_existing_files_as_leaf_targets
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("input.txt", "data")

        tasks = {
          "all" => TaskRunner::Task.new("all", ["input.txt"], ["echo all"], 1)
        }

        resolved = TaskRunner::RuleResolver.new(
          tasks: tasks,
          rules: [],
          phony_targets: Set.new
        ).resolve("all")

        assert_equal ["input.txt", "all"], resolved.keys
        assert_equal [], resolved["input.txt"].dependencies
        assert_equal [], resolved["input.txt"].commands
      end
    end
  end
end
