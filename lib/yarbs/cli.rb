# frozen_string_literal: true

require "optparse"
require_relative "cli/init"

module Yarbs
  # The `yarbs` command line executable.
  module CLI
    # Parses ARGV and runs yarbs from the command line.
    #
    # @param argv [Array<String>]
    # @return [void]
    def self.run(argv)
      return init(argv.drop(1)) if argv.first == "init"

      output_dir = nil
      watch = false
      strict = false

      parser = OptionParser.new do |opts|
        opts.banner = <<~BANNER
          Usage: yarbs [options] [GLOB ...]
                 yarbs init [options] [GLOB ...]

          With no GLOB, uses the paths in #{Config::FILE} (or lib/**/*.rb).
        BANNER
        opts.on("-o", "--output DIR", "Directory to write .rbs files into (default: sig)") do |dir|
          output_dir = dir
        end
        opts.on("-w", "--watch", "Watch the matched files and regenerate on change") do
          watch = true
        end
        opts.on("-s", "--strict", "Raise instead of falling back to `untyped` on a YARD documentation error") do
          strict = true
        end
      end

      patterns = parser.parse(argv)

      config = begin
        Config.load
      rescue Error => e
        warn e.message
        exit 1
      end
      patterns = config.paths if patterns.empty?
      output_dir ||= config.output
      # The config's `strict` is ignored in watch mode rather than rejected,
      # so a project can set it for one-off runs and still use --watch.
      strict ||= config.strict unless watch

      if strict && watch
        warn "yarbs: --strict cannot be combined with --watch"
        exit 1
      end

      return Watcher.new(patterns, output_dir: output_dir).run if watch

      begin
        written = Yarbs.generate(patterns, output_dir: output_dir, strict: strict)
      rescue Error => e
        warn e.message
        exit 1
      end

      if written.empty?
        warn "yarbs: no files matched #{patterns.join(" ")}"
        exit 1
      end

      written.each { |path| puts "wrote #{path}" }
    end

    # Runs `yarbs init`.
    #
    # @param argv [Array<String>] the arguments after `init`
    # @return [void]
    def self.init(argv)
      dry_run = false
      install = true

      parser = OptionParser.new do |opts|
        opts.banner = <<~BANNER
          Usage: yarbs init [options] [GLOB ...]

          Sets up #{Config::FILE}, a Steepfile, rbs_collection.yaml and .gitignore
          entries, then generates signatures. Existing files are never overwritten.
          GLOB defaults to lib/**/*.rb.
        BANNER
        opts.on("-n", "--dry-run", "Show what would be done without writing anything") do
          dry_run = true
        end
        opts.on("--no-install", "Don't run `rbs collection install`") do
          install = false
        end
      end

      paths = parser.parse(argv)

      begin
        Init.run(paths: paths.empty? ? nil : paths, dry_run: dry_run, install: install)
      rescue Error => e
        warn e.message
        exit 1
      end
    end
  end
end
