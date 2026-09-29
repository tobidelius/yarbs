# frozen_string_literal: true

require "bundler"
require "rbs"
require "rbs/cli"
require "stringio"

module Yarbs
  module CLI
    # `yarbs init`: sets a project up to use yarbs with Steep, so the
    # signatures it writes are actually checked.
    #
    # Every step is safe to re-run: files that already exist are left alone
    # (and reported as skipped), and `.gitignore` only gets the entries it's
    # missing.
    class Init
      STEEPFILE = "Steepfile"
      RBS_COLLECTION = "rbs_collection.yaml"
      GITIGNORE = ".gitignore"
      GEM_RBS_COLLECTION_DIR = "/.gem_rbs_collection/"
      RBS_COLLECTION_LOCK = "/rbs_collection.lock.yaml"

      # Runs every setup step in the current directory.
      #
      # @param paths [Array<String>, nil] glob patterns to write into a new
      #   .yarbs.yml (defaults to +lib/**/*.rb+)
      # @param dry_run [Boolean] report what would change without writing anything
      # @param install [Boolean] run +rbs collection install+ afterwards
      # @param out [IO] where to report each step
      # @return [void]
      def self.run(paths: nil, dry_run: false, install: true, out: $stdout)
        new(paths, dry_run, install, out).run
      end

      def initialize(paths, dry_run, install, out)
        @paths = paths
        @dry_run = dry_run
        @install = install
        @out = out
      end

      def run
        report "dry run", "nothing will be written" if @dry_run

        config = write_config
        create_file(STEEPFILE, steepfile(config))
        create_file(RBS_COLLECTION, rbs_collection)
        update_gitignore
        install_collection
        generate(config)

        return if Gem::Specification.find_all_by_name("steep").any?

        report "next", "add Steep to type-check against the signatures: bundle add steep --group development"
      end

      private

      # An existing .yarbs.yml wins over any paths given to `init`, so the
      # Steepfile always matches what `yarbs` will actually generate.
      def write_config
        if File.exist?(Config::FILE)
          report "skip", "#{Config::FILE} (already exists)"
          return Config.load
        end

        config = @paths ? Config.new(paths: @paths) : Config.new
        create_file(Config::FILE, config.to_yaml)
        config
      end

      # @param config [Config]
      # @return [String]
      def steepfile(config)
        checks = config.paths.map { |pattern| Watcher.base_directory(pattern) }.uniq

        <<~RUBY
          D = Steep::Diagnostic

          target :app do
            signature #{config.output.inspect}

            #{checks.map { |dir| "check #{dir.inspect}" }.join("\n  ")}

            # Lenient to start with, since most of a codebase is `untyped` until
            # it's documented. Tighten this (D::Ruby.default, D::Ruby.strict)
            # as more of it gets YARD types.
            configure_code_diagnostics(D::Ruby.lenient)
          end
        RUBY
      end

      # @return [String]
      def rbs_collection
        <<~YAML
          # Where Steep gets type signatures for your gems from.
          # Run `rbs collection install` after changing your Gemfile.
          sources:
            - type: git
              name: ruby/gem_rbs_collection
              remote: https://github.com/ruby/gem_rbs_collection.git
              revision: main
              repo_dir: gems

          # A directory to install the downloaded RBSs
          path: .gem_rbs_collection

          # gems:
          #   # If you want to avoid installing rbs files for gems, you can specify them here.
          #   - name: GEM_NAME
          #     ignore: true
        YAML
      end

      def create_file(path, contents)
        if File.exist?(path)
          report "skip", "#{path} (already exists)"
          return
        end

        File.write(path, contents) unless @dry_run
        report "create", path
      end

      # A gem's rbs_collection.lock.yaml is conventionally not committed (its
      # users resolve their own), but an app should commit it, just like its
      # Gemfile.lock.
      def gitignore_entries
        entries = [GEM_RBS_COLLECTION_DIR]
        entries << RBS_COLLECTION_LOCK if Dir.glob("*.gemspec").any?
        entries
      end

      def update_gitignore
        exists = File.exist?(GITIGNORE)
        unless exists || Dir.exist?(".git")
          report "skip", "#{GITIGNORE} (not a git repository)"
          return
        end

        contents = exists ? File.read(GITIGNORE) : ""
        present = contents.lines.map { |line| normalize_ignore(line) }
        missing = gitignore_entries.reject { |entry| present.include?(normalize_ignore(entry)) }

        if missing.empty?
          report "skip", "#{GITIGNORE} (already has yarbs' entries)"
          return
        end

        unless @dry_run
          separator = (contents.empty? || contents.end_with?("\n")) ? "" : "\n"
          File.write(GITIGNORE, contents + separator + missing.join("\n") + "\n")
        end
        report exists ? "update" : "create", "#{GITIGNORE} (added #{missing.join(", ")})"
      end

      # `/.gem_rbs_collection/`, `.gem_rbs_collection/` and
      # `.gem_rbs_collection` all ignore the same thing at the project root,
      # so compare them without the leading/trailing slash.
      def normalize_ignore(line)
        line.strip.delete_prefix("/").delete_suffix("/")
      end

      def install_collection
        return unless @install

        unless File.exist?("Gemfile")
          report "skip", "rbs collection install (no Gemfile)"
          return
        end

        if @dry_run
          report "run", "rbs collection install"
          return
        end

        report "run", "rbs collection install"
        output = StringIO.new
        RBS::CLI.new(stdout: output, stderr: output).run(%w[collection install])
      rescue StandardError, SystemExit => e
        report "failed", "rbs collection install (#{e.message}); run it yourself once that's fixed"
      end

      def generate(config)
        if @dry_run
          report "run", "yarbs #{config.paths.join(" ")} -o #{config.output}"
          return
        end

        written = Yarbs.generate(config.paths, output_dir: config.output, strict: config.strict)
        if written.empty?
          report "skip", "generating signatures (no files matched #{config.paths.join(" ")})"
        else
          report "wrote", "#{written.size} file#{"s" unless written.size == 1} to #{config.output}/"
        end
      end

      def report(action, message)
        @out.puts "#{action.rjust(8)}  #{message}"
      end
    end
  end
end
