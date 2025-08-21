#!/usr/bin/env ruby

# Usage: ruby test_analyzer.rb <log_file_path>

if ARGV.empty?
  puts "Usage: #{$0} <log_file_path>"
  exit 1
end

log_file = ARGV[0]

unless File.exist?(log_file)
  puts "Error: File '#{log_file}' not found"
  exit 1
end

# Track test executions
created_tests = {}
begun_tests = {}
finished_tests = {}

# Parse the log file
File.foreach(log_file) do |line|
  # Match CREATE lines
  if match = line.match(/CREATE TestCaseExecution ([A-F0-9-]+): (.+)$/)
    test_id = match[1]
    test_name = match[2]
    created_tests[test_id] = test_name
  end
  
  # Match BEGIN lines
  if match = line.match(/BEGIN TestCaseExecution ([A-F0-9-]+): (.+)$/)
    test_id = match[1]
    test_name = match[2]
    begun_tests[test_id] = test_name
  end
  
  # Match FINISH lines
  if match = line.match(/FINISH TestCaseExecution ([A-F0-9-]+): (.+)$/)
    test_id = match[1]
    result = match[2]
    finished_tests[test_id] = result
  end
end

# Find tests that were created/begun but never finished
unfinished_tests = []

created_tests.each do |test_id, test_name|
  unless finished_tests.key?(test_id)
    status = begun_tests.key?(test_id) ? "BEGUN" : "CREATED"
    unfinished_tests << {
      id: test_id,
      name: test_name,
      status: status
    }
  end
end

# Output results
puts "Test Execution Analysis"
puts "=" * 50
puts "Total tests created: #{created_tests.size}"
puts "Total tests begun: #{begun_tests.size}"
puts "Total tests finished: #{finished_tests.size}"
puts "Unfinished tests: #{unfinished_tests.size}"
puts

if unfinished_tests.empty?
  puts "✅ All tests completed!"
else
  puts "❌ Tests that did not finish:"
  puts
  
  unfinished_tests.each_with_index do |test, index|
    puts "#{index + 1}. #{test[:id]} (#{test[:status]})"
    puts "   #{test[:name]}"
    puts
  end
end

# Summary by status
created_only = unfinished_tests.select { |t| t[:status] == "CREATED" }
begun_only = unfinished_tests.select { |t| t[:status] == "BEGUN" }

if created_only.any?
  puts "Tests that were CREATED but never BEGUN (#{created_only.size}):"
  created_only.each { |t| puts "  - #{t[:name]}" }
  puts
end

if begun_only.any?
  puts "Tests that were BEGUN but never FINISHED (#{begun_only.size}):"
  begun_only.each { |t| puts "  - #{t[:name]}" }
  puts
end

# Show some finished test results summary
success_count = finished_tests.values.count("success")
error_count = finished_tests.values.count { |result| result.start_with?("error") }

puts "Finished test results:"
puts "  ✅ Success: #{success_count}"
puts "  ❌ Error: #{error_count}"

if error_count > 0
  puts
  puts "Common error patterns:"
  error_patterns = Hash.new(0)
  finished_tests.values.each do |result|
    if result.start_with?("error")
      if result.include?("connection limit exceeded")
        error_patterns["Connection limit exceeded"] += 1
      elsif result.include?("ExpectationFailedError")
        error_patterns["Expectation failed"] += 1
      else
        error_patterns["Other error"] += 1
      end
    end
  end
  
  error_patterns.each do |pattern, count|
    puts "  - #{pattern}: #{count}"
  end
end