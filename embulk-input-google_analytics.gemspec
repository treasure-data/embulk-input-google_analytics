
Gem::Specification.new do |spec|
  spec.name          = "embulk-input-google_analytics"
  spec.version       = "0.1.0"
  spec.authors       = ["uu59"]
  spec.summary       = "Google Analytics input plugin for Embulk"
  spec.description   = "Loads records from Google Analytics."
  spec.email         = ["k@uu59.org"]
  spec.licenses      = ["MIT"]
  # TODO set this: spec.homepage      = "https://github.com/k/embulk-input-google_analytics"

  spec.files         = `git ls-files`.split("\n") + Dir["classpath/*.jar"]
  spec.test_files    = spec.files.grep(%r{^(test|spec)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "httpclient"
  spec.add_dependency "google-api-client", "~> 0.9"
  spec.add_dependency "signet"
  spec.add_dependency "tzinfo"
  # spec.add_dependency "googleauth", "~> 0.4.2"
  # spec.add_dependency "google-api-client", "~> 0.8.6"
  spec.add_development_dependency 'embulk', ['>= 0.8.9']
  spec.add_development_dependency 'bundler', ['>= 1.10.6']
  spec.add_development_dependency 'rake', ['>= 10.0']
  spec.add_development_dependency "pry"
end
