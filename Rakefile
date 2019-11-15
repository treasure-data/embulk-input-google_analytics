require "bundler/gem_tasks"
require "gem_release_helper/tasks"

task default: :test # TODO: weida default and use [rake] to build 

desc "Run tests"
task :test do
  ruby("--debug", "test/run-test.rb", "--use-color=yes", "--collector=dir")
end

desc "Run tests with coverage"
task :cov do
  ENV["COVERAGE"] = "1"
  ruby("--debug", "test/run-test.rb", "--use-color=yes", "--collector=dir")
end

GemReleaseHelper::Tasks.install({
  gemspec: "./embulk-input-google_analytics.gemspec",
  github_name: "treasure-data/embulk-input-google_analytics",
})
