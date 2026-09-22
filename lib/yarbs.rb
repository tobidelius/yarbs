# frozen_string_literal: true

require "yard"
require "rbs"

require_relative "yarbs/version"
require_relative "yarbs/type_converter"
require_relative "yarbs/prototype_builder"
require_relative "yarbs/annotator"
require_relative "yarbs/generator"
require_relative "yarbs/watcher"
require_relative "yarbs/cli"

module Yarbs
  class Error < StandardError; end

  # Generates .rbs signature files for the Ruby source files matched by
  # +patterns+, writing them into +output_dir+.
  #
  # @param patterns [Array<String>] glob patterns for Ruby source files
  # @param output_dir [String] directory to write generated .rbs files into
  # @param strict [Boolean] raise a {Yarbs::Error} instead of skipping a file
  #   or falling back to +untyped+ when something can't be converted
  # @return [Array<Pathname>] paths of the files written
  def self.generate(patterns, output_dir: "sig", strict: false)
    Generator.run(Array(patterns), output_dir: output_dir, strict: strict)
  end
end
