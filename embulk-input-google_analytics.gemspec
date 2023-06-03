
Gem::Specification.new do |spec|
  spec.name          = "embulk-input-google_analytics"
	spec.version       = "0.1.24"
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
  spec.add_dependency "google-api-client", [">= 0.11", "< 0.33.0"]
  # signet version > 11.0 requires Ruby version >= 2.4
  # activesupport version > 5.2.3 requires Ruby version >= 2.5
  # representable veresion > 3.1.0 requires Ruby version >= 2.4
  # Current embulk version 0.9.19 runs under jRuby 9.1.x (which is compatible with Ruby 2.3)
  # So decide to lock these gem versions to prevent incompatible Ruby version
  spec.add_dependency "signet", ['~> 0.7', "< 0.11.0"]
  spec.add_dependency "activesupport", "<= 5.2.3" # for Time.zone.parse, Time.zone.now
  spec.add_dependency "representable", ['~> 3.0.0', '< 3.1']

  spec.add_dependency "perfect_retry", "~> 0.5"

  spec.add_development_dependency 'embulk', ['>= 0.8.9']
  spec.add_development_dependency 'bundler', ['>= 1.10.6']
  spec.add_development_dependency 'rake', ['>= 10.0']
  spec.add_development_dependency 'test-unit', ['< 3.2']
  spec.add_development_dependency 'test-unit-rr'
  # Lock simple cov and simplecov-html to prevent downloaded newer version which require ruby >= 2.4
  # Current embulk version 0.9.19 runs under jRuby 9.1.x (which is compatible with Ruby 2.3)
  spec.add_development_dependency 'simplecov', ['<= 0.12.0']
  spec.add_development_dependency 'simplecov-html', ['<= 0.12.0']
  spec.add_development_dependency "codeclimate-test-reporter"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "gem_release_helper", "~> 1.0"
end
