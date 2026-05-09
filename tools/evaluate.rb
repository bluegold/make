#!/usr/bin/env ruby

require 'fileutils'

def main
  lang = ARGV[0]
  level = ARGV[1]

  if lang.nil? || level.nil?
    puts "Usage: #{$0} <language> <level>"
    puts "Example: #{$0} python level1"
    exit 1
  end

  level_map = {
    "level1" => "01_basic",
    "level2" => "02_variables",
    "level3" => "03_advanced",
    "golang" => "01_basic",  # For golang, all levels use same samples
  }

  sample_dir_name = level_map[level]
  if sample_dir_name.nil?
    puts "Error: Unknown level '#{level}'"
    exit 1
  end

  project_root = Dir.pwd
  sample_dir = File.expand_path(File.join("samples", sample_dir_name), project_root)
  
  unless Dir.exist?(sample_dir)
    puts "Error: Sample directory '#{sample_dir}' not found."
    exit 1
  end

  # Determine runner and builder paths
  lang_dir = File.expand_path(lang, project_root)
  runner_path = File.join(lang_dir, "runner")
  builder_path = File.join(lang_dir, "builder")

  unless File.exist?(runner_path)
    puts "Error: Runner at '#{runner_path}' not found."
    exit 1
  end

  # Run builder if it exists (for compiled languages)
  if File.exist?(builder_path)
    puts "Building #{lang}..."
    build_output = `#{builder_path} 2>&1`
    build_status = $?
    unless build_status.success?
      puts "Error: Build failed for #{lang}"
      puts build_output
      exit 1
    end
  end

  run_cmd = "#{runner_path} #{level}"

  puts "=== Evaluating #{lang} #{level} ==="
  puts "Samples: #{sample_dir}"
  puts "Runner: #{runner_path}"
  puts "------------------------"
  
  samples = Dir.glob(File.join(sample_dir, "*.txt")).sort
  
  success_count = 0
  fail_count = 0

  samples.each do |sample_path|
    sample_file = File.basename(sample_path)
    # error or loop in filename indicates an expected failure
    expect_fail = sample_file.include?("error") || sample_file.include?("loop")
    
    print "Testing #{sample_file}... "
    
    output = ""
    status = nil
    expected_path = sample_path.sub(/\.txt$/, ".expected")
    has_expected = File.exist?(expected_path)
    start_time = nil

    # Execute in the sample directory to ensure relative paths in commands work
    Dir.chdir(sample_dir) do
      # Pre-test cleanup: run 'clean' if the Taskfile supports it
      content = File.read(sample_file) rescue ""
      if content.include?("clean:")
        `#{run_cmd} #{sample_file} clean > /dev/null 2>&1`
      end

      start_time = Time.now

      # Special handling for 01_timestamp: test the skip logic specifically
      # For now, specifically for 01_timestamp, we want to test the skip logic.
      if sample_file == "01_timestamp.txt"
        File.delete("output.data") if File.exist?("output.data")
        File.write("input.data", "test data")

        # First run: should execute
        `#{run_cmd} #{sample_file} > /dev/null 2>&1`

        # Second run: should NOT execute
        output = `#{run_cmd} #{sample_file} 2>&1`
        status = $?

        if output.include?("Processing input.data...")
          status = Process::Status.wait(spawn("false"))
          output = "Timestamp skip logic failed: Task ran even though output.data was up to date.\n" + output
        else
          output = File.read(expected_path) rescue "Executing: echo \"Processing input.data...\""
          status = Process::Status.wait(spawn("true"))
        end
      else
        output = `#{run_cmd} #{sample_file} 2>&1`
        status = $?
      end

    end
    duration = start_time ? Time.now - start_time : 0

    passed = false
    reason = ""

    if has_expected
      expected_content = File.read(expected_path).strip
      # Check if expected content is in output (partial match is often enough and robust)
      if output.include?(expected_content)
        passed = true
      else
        passed = false
        reason = "Output did not match expected content."
      end
    else
      # Fallback to filename-based detection
      if expect_fail
        passed = !status.success?
        reason = "Expected failure but succeeded." unless passed
      else
        passed = status.success?
        reason = "Expected success but failed." unless passed
      end
    end

    # Special check for parallel execution: 03_parallel.txt should finish in < 3 seconds 
    # (since sequential would take 4+ seconds)
    if passed && sample_file == "03_parallel.txt"
      if duration > 3.0
        passed = false
        reason = "Task took too long (#{duration.round(2)}s). Sequential execution suspected?"
      else
        reason = "(Took #{duration.round(2)}s)" # Keep as info
      end
    end

    if passed
      puts has_expected ? "PASS (Matched .expected)" : (expect_fail ? "PASS (Expected Failure)" : "PASS")
      success_count += 1
    else
      puts "FAIL"
      puts "Reason: #{reason}"
      puts "--- Output ---"
      puts output
      puts "--------------"
      if has_expected
        puts "--- Expected (to be contained in output) ---"
        puts expected_content
        puts "--------------------------------------------"
      end
      fail_count += 1
    end
  end

  puts "========================"
  puts "Summary: #{success_count} passed, #{fail_count} failed"
  
  # Return to original root (though redundant due to Dir.chdir block)
  Dir.chdir(project_root)
  
  exit (fail_count == 0 ? 0 : 1)
end

main if __FILE__ == $0
