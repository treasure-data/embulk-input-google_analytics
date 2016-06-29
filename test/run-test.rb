#!/usr/bin/env ruby

base_dir = File.expand_path(File.join(File.dirname(__FILE__), ".."))
lib_dir = File.join(base_dir, "lib")
test_dir = File.join(base_dir, "test")

require "test-unit"
require "test/unit/rr"

$LOAD_PATH.unshift(lib_dir)
$LOAD_PATH.unshift(test_dir)

ENV["TEST_UNIT_MAX_DIFF_TARGET_STRING_SIZE"] ||= "5000"

if ENV["COVERAGE"]
  require 'simplecov'
  SimpleCov.start 'test_frameworks'

  if ENV['CIRCLE_ARTIFACTS'] # https://circleci.com/docs/code-coverage
    dir = File.join(ENV['CIRCLE_ARTIFACTS'], "coverage")
    SimpleCov.coverage_dir(dir)
  end
end

exit Test::Unit::AutoRunner.run(true, test_dir)
