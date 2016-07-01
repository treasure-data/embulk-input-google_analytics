require "bundler/gem_tasks"

task default: :test

desc "Run tests"
task :test do
  ruby("--debug", "test/run-test.rb", "--use-color=yes", "--collector=dir")
end

desc "Run tests with coverage"
task :cov do
  ENV["COVERAGE"] = "1"
  ruby("--debug", "test/run-test.rb", "--use-color=yes", "--collector=dir")
end

