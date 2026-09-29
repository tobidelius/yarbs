# frozen_string_literal: true

require "yaml"

module Yarbs
  # The settings in a project's +.yarbs.yml+, so that a plain +yarbs+ (or
  # +yarbs --watch+) knows what to generate without repeating the globs on
  # every run. Written by +yarbs init+; anything given on the command line
  # overrides it.
  class Config
    # The config file yarbs looks for in the current directory.
    FILE = ".yarbs.yml"

    DEFAULT_PATHS = ["lib/**/*.rb"].freeze
    DEFAULT_OUTPUT = "sig"
    KEYS = %w[paths output strict].freeze

    # @return [Array<String>] glob patterns for Ruby source files
    attr_reader :paths

    # @return [String] directory to write generated .rbs files into
    attr_reader :output

    # @return [Boolean] raise instead of falling back to +untyped+
    attr_reader :strict

    # Loads the config file, or the defaults if there isn't one.
    #
    # @param path [String] the config file to read
    # @return [Config]
    # @raise [Error] if the file isn't valid YAML or has an unknown or
    #   mistyped setting
    def self.load(path = FILE)
      return new unless File.exist?(path)

      data = YAML.safe_load_file(path) || {}
      raise Error, "yarbs: #{path} must be a YAML mapping" unless data.is_a?(Hash)

      unknown = data.keys - KEYS
      raise Error, "yarbs: unknown setting#{"s" unless unknown.size == 1} in #{path}: #{unknown.join(", ")}" if unknown.any?

      new(
        paths: Array(data.fetch("paths", DEFAULT_PATHS)),
        output: data.fetch("output", DEFAULT_OUTPUT),
        strict: data.fetch("strict", false)
      ).tap { |config| config.validate!(path) }
    rescue Psych::Exception => e
      raise Error, "yarbs: could not parse #{path} (#{e.message})"
    end

    # @param paths [Array<String>]
    # @param output [String]
    # @param strict [Boolean]
    def initialize(paths: DEFAULT_PATHS, output: DEFAULT_OUTPUT, strict: false)
      @paths = paths
      @output = output
      @strict = strict
    end

    # @param path [String] the config file, for the error message
    # @return [void]
    # @raise [Error]
    def validate!(path)
      raise Error, "yarbs: `paths` in #{path} must be a list of glob strings" unless paths.all?(String) && paths.any?
      raise Error, "yarbs: `output` in #{path} must be a directory name" unless output.is_a?(String)
      raise Error, "yarbs: `strict` in #{path} must be true or false" unless [true, false].include?(strict)
    end

    # The YAML written to a new config file.
    #
    # @return [String]
    def to_yaml
      <<~YAML
        # Settings for yarbs (https://github.com/tobidelius/yarbs).
        # Anything passed on the command line overrides these.

        # Glob patterns for the Ruby files to generate signatures for.
        paths:
        #{paths.map { |path| "  - #{path.inspect}" }.join("\n")}

        # Directory the generated .rbs files are written into.
        output: #{output}

        # Raise instead of falling back to `untyped` when a YARD type can't
        # be converted. Ignored by `yarbs --watch`.
        strict: #{strict}
      YAML
    end
  end
end
