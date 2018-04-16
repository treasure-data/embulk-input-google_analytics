
Gem::Specification.new do |spec|
  spec.name          = "embulk-input-google_analytics"
	spec.version       = "0.1.17"
  spec.authors       = ["uu59"]
  spec.summary       = "Google Analytics input plugin for Embulk"
  spec.description   = "Loads records from Google Analytics."
  spec.email         = ["k@uu59.org"]
  spec.licenses      = ["MIT"]
  spec.homepage      = "https://github.com/treasure-data/embulk-input-google_analytics"

  spec.files         = `git ls-files`.split("\n") + Dir["classpath/*.jar"]
  spec.test_files    = spec.files.grep(%r{^(test|spec)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "httpclient"
  spec.add_dependency "google-api-client", "0.10.1"
  spec.add_dependency "signet"
  spec.add_dependency "activesupport" # for Time.zone.parse, Time.zone.now
  spec.add_dependency "perfect_retry", "~> 0.5"

  spec.add_development_dependency 'embulk', ['>= 0.8.9']
  spec.add_development_dependency 'bundler', ['>= 1.10.6']
  spec.add_development_dependency 'rake', ['>= 10.0']
  spec.add_development_dependency 'test-unit'
  spec.add_development_dependency 'test-unit-rr'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency "codeclimate-test-reporter"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "gem_release_helper", "~> 1.0"
end
