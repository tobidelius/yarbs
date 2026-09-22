# frozen_string_literal: true

require "listen"
require "pathname"

module Yarbs
  # Watches the files matched by a set of glob patterns (using the `listen`
  # gem) and regenerates their RBS signatures whenever one of them changes.
  #
  # Used by `yarbs --watch` while developing an app with Yarbs support.
  class Watcher
    # Sets up a watcher for the given glob patterns.
    #
    # @param patterns [Array<String>] glob patterns for Ruby source files
    # @param output_dir [String] directory to write generated .rbs files into
    def initialize(patterns, output_dir:)
      @patterns = patterns
      @output_dir = output_dir
    end

    # Starts watching and blocks until interrupted (Ctrl-C).
    #
    # @return [void]
    def run
      generate("starting up")

      directories = watch_directories
      if directories.empty?
        warn "yarbs: nothing to watch for #{@patterns.join(" ")}"
        return
      end

      listener = Listen.to(*directories) { |modified, added, removed| on_change(modified + added + removed) }
      listener.start

      wait_for_interrupt
    ensure
      listener&.stop
      puts "yarbs: stopped watching"
    end

    private

    def wait_for_interrupt
      stopped = false
      trap("INT") { stopped = true }
      sleep 0.2 until stopped
    end

    def on_change(paths)
      changed = paths.select { |path| matches_patterns?(path) }
      return if changed.empty?

      generate("#{changed.size} file#{"s" unless changed.size == 1} changed")
    end

    def generate(reason)
      puts "yarbs: #{reason}, regenerating..."
      written = Yarbs.generate(@patterns, output_dir: @output_dir)
      puts "yarbs: wrote #{written.size} file#{"s" unless written.size == 1} to #{@output_dir}"
    rescue => e
      warn "yarbs: #{e.class}: #{e.message}"
    end

    def matches_patterns?(path)
      relative = relative_path(path)
      @patterns.any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Pathname.pwd).to_s
    rescue ArgumentError
      path
    end

    def watch_directories
      @patterns.filter_map { |pattern| base_directory(pattern) }.uniq.select { |dir| Dir.exist?(dir) }
    end

    # The directory to hand to `Listen.to` for a glob pattern: everything
    # before its first glob character, e.g. "lib/**/*.rb" -> "lib".
    def base_directory(pattern)
      glob_index = pattern.index(/[*?{\[]/)
      return File.dirname(pattern) unless glob_index

      prefix = pattern[0...glob_index]
      return "." if prefix.empty?

      prefix.end_with?("/") ? prefix.chomp("/") : File.dirname(prefix)
    end
  end
end
