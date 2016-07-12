require_relative "lib/rubber_duck/version"

Gem::Specification.new do |s|
  s.name        = 'rubber_duck'
  s.version       = RubberDuck::VERSION
  s.licenses    = ['MIT']
  s.summary     = "Simple Control Flow Analysis for Ruby Programs"
  s.description = "Simple Control Flow Analysis for Ruby Programs"
  s.authors     = ["Soutaro Matsumoto"]
  s.email       = 'matsumoto@soutaro.com'
  s.homepage    = 'https://github.com/soutaro/rubber_duck'

  s.files         = `git ls-files -z`.split("\x0")
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.add_development_dependency "rake", "~> 10.0"
  s.add_development_dependency "minitest", "~> 5.8"

  s.add_dependency 'parser', '~> 2.3'
  s.add_dependency 'defsdb', '~> 0.1'
end
