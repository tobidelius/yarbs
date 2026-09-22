# frozen_string_literal: true

require "pathname"
require "rbs"
require "yard"

module Yarbs
  # Orchestrates a full run: expands the glob patterns, loads YARD
  # documentation for the matched files, and writes an annotated +.rbs+ file
  # per source file into the output directory.
  class Generator
    # Runs a full generation pass for the given glob patterns.
    #
    # @param patterns [Array<String>] glob patterns for Ruby source files
    # @param output_dir [String] directory to write generated .rbs files into
    # @param strict [Boolean] raise instead of skipping a file or falling
    #   back to +untyped+ when something can't be converted
    # @return [Array<Pathname>] paths of the files written
    def self.run(patterns, output_dir: "sig", strict: false)
      new(output_dir, strict).run(patterns)
    end

    def initialize(output_dir, strict = false)
      @output_dir = Pathname.new(output_dir)
      @strict = strict
    end

    def run(patterns)
      files = patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.select { |file| File.file?(file) }
      return [] if files.empty?

      # `YARD.parse` only populates the in-memory Registry: unlike
      # `YARD::Registry.load`, it neither reads nor writes a `.yardoc` cache
      # directory, so each run reflects exactly the files we were given.
      YARD::Registry.clear
      YARD.parse(files)

      files.filter_map { |file| generate_file(file) }
    end

    private

    # A single file with a (possibly transient, e.g. mid-edit) syntax error
    # shouldn't stop the rest of the batch from generating: skip it and warn,
    # unless running in strict mode, where it's treated as a hard failure.
    def generate_file(file)
      decls = PrototypeBuilder.build(File.read(file))
      annotated = Annotator.annotate(decls, strict: @strict)

      out_path = @output_dir.join(relative_sig_path(file))
      out_path.dirname.mkpath
      out_path.open("w") { |io| RBS::Writer.new(out: io).write(annotated) }

      out_path
    rescue SyntaxError => e
      raise Error, "yarbs: syntax error in #{file} (#{e.message})" if @strict

      warn "yarbs: skipping #{file} (#{e.message})"
      nil
    end

    # Mirrors the source file's path under the output directory, stripping a
    # leading `lib/` or `app/` (the conventional Ruby load-path roots) so
    # `lib/foo/bar.rb` becomes `<output_dir>/foo/bar.rbs`.
    def relative_sig_path(file)
      parts = Pathname.new(file).cleanpath.each_filename.to_a
      parts.shift if %w[lib app].include?(parts.first)
      parts[-1] = parts[-1].sub(/\.rb\z/, ".rbs")
      Pathname.new(File.join(*parts))
    end
  end
end
