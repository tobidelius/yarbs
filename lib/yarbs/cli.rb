# frozen_string_literal: true

require "optparse"

module Yarbs
  # The `yarbs` command line executable.
  module CLI
    # Parses ARGV and runs yarbs from the command line.
    #
    # @param argv [Array<String>]
    # @return [void]
    def self.run(argv)
      output_dir = "sig"
      watch = false
      strict = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: yarbs [options] GLOB [GLOB ...]"
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

      if patterns.empty?
        warn parser.help
        exit 1
      end

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
  end
end
