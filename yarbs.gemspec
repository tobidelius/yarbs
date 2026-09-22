# frozen_string_literal: true

require_relative "lib/yarbs/version"

Gem::Specification.new do |spec|
  spec.name = "yarbs"
  spec.version = Yarbs::VERSION
  spec.authors = ["tobidelius"]
  spec.email = ["tobidelius@gmail.com"]

  spec.summary = "Generate RBS files from YARD documentation."
  spec.homepage = "https://github.com/tobidelius/yarbs"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "lib/**/*.rb",
      "sig/**/*.rbs",
      "exe/*",
      "README.md",
      "LICENSE.txt",
      "Rakefile"
    ]
  end
  spec.bindir = "exe"
  spec.executables << "yarbs"
  spec.require_paths = ["lib"]

  spec.add_dependency "listen", "~> 3.9"
  spec.add_dependency "rbs", "~> 4.2"
  spec.add_dependency "yard", "~> 0.9"
end
