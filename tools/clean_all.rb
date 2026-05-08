#!/usr/bin/env ruby

require 'fileutils'

def clean_level(lang, level, sample_dir_name)
  project_root = Dir.pwd
  sample_dir = File.expand_path(File.join("samples", sample_dir_name), project_root)
  
  unless Dir.exist?(sample_dir)
    puts "Skipping #{level}: Directory not found."
    return
  end

  impl_path = File.expand_path(File.join(lang, level, "src", "main.py"), project_root)
  unless File.exist?(impl_path)
    puts "Skipping #{level}: Implementation not found."
    return
  end

  puts "--- Cleaning #{level} ---"
  
  samples = Dir.glob(File.join(sample_dir, "*.txt")).sort
  samples.each do |sample_path|
    sample_file = File.basename(sample_path)
    
    # Check if the Taskfile has a clean target
    content = File.read(sample_path)
    if content.include?("clean:")
      puts "Cleaning #{sample_file}..."
      Dir.chdir(sample_dir) do
        system("python3 #{impl_path} #{sample_file} clean > /dev/null 2>&1")
      end
    end
  end
end

def main
  lang = "python"
  levels = {
    "level1" => "01_basic",
    "level2" => "02_variables",
    "level3" => "03_advanced"
  }

  levels.each do |level, dir|
    clean_level(lang, level, dir)
  end

  # Special cleanup for Level 3 extra files that don't have a 'clean' target in Taskfile
  puts "--- Cleaning extra files ---"
  extra_files = Dir.glob("samples/03_advanced/*.{md,data}")
  extra_files.each do |f|
    puts "Removing #{f}"
    FileUtils.rm_f(f)
  end

  puts "Done."
end

main if __FILE__ == $0
