# frozen_string_literal: true

require "test_helper"
require "fileutils"

class GeneratorTest < Minitest::Test
  def test_generate_merges_yard_types_into_the_rbs_structure
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/widget.rb", <<~RUBY)
          module Sample
            class Widget
              # Builds a widget.
              #
              # @param name [String] the widget's name
              # @param count [Integer, nil] how many to build
              # @yieldparam progress [Integer] percent complete
              # @return [Boolean] whether it worked
              def build(name, count: nil)
                yield 1
                true
              end

              # @return [String] the label
              attr_reader :label

              # @return [Integer]
              MAX = 10
            end
          end
        RUBY

        written = Yarbs.generate(["lib/**/*.rb"], output_dir: "sig")

        assert_equal ["sig/widget.rbs"], written.map(&:to_s)
        contents = File.read("sig/widget.rbs")

        assert_includes contents, "def build: (String name, ?count: Integer | nil) { (Integer progress) -> untyped } -> bool"
        assert_includes contents, "attr_reader label: String"
        assert_includes contents, "MAX: Integer"

        RBS::Parser.parse_signature(contents)
      end
    end
  end

  def test_generate_returns_empty_array_when_no_files_match
    Dir.mktmpdir do |dir|
      assert_equal [], Yarbs.generate([File.join(dir, "**", "*.rb")], output_dir: File.join(dir, "sig"))
    end
  end

  def test_a_file_with_invalid_syntax_is_skipped_and_the_rest_still_generate
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/broken.rb", "class Broken\n  def foo(\n  end\nend\n")
        File.write("lib/ok.rb", "class Ok\nend\n")

        written = nil
        _, err = capture_io { written = Yarbs.generate(["lib/**/*.rb"], output_dir: "sig") }

        assert_equal ["sig/ok.rbs"], written.map(&:to_s)
        assert_match(/skipping lib\/broken\.rb/, err)
      end
    end
  end

  def test_strict_raises_on_invalid_syntax_instead_of_skipping
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/broken.rb", "class Broken\n  def foo(\n  end\nend\n")

        error = assert_raises(Yarbs::Error) { Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true) }
        assert_match(/syntax error in lib\/broken\.rb/, error.message)
      end
    end
  end

  def test_rest_params_are_unwrapped_to_their_element_type
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/widget.rb", <<~RUBY)
          class Widget
            # @param names [Array<String>] any number of names
            # @param opts [Hash{Symbol => Integer}] any number of options
            # @return [void]
            def build(*names, **opts)
            end
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/widget.rbs")

        assert_includes contents, "def build: (*String names, **Integer opts) -> void"
      end
    end
  end

  def test_option_tags_build_a_record_type_for_a_plain_hash_param
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/mailer.rb", <<~RUBY)
          class Mailer
            # @param opts [Hash] the options to create a message with
            # @option opts [String] :subject the subject
            # @option opts [String] :from ('nobody') from address
            # @option opts [Boolean, nil] :urgent whether it's urgent
            # @return [void]
            def send_message(opts = {})
            end

            # @option settings [String] :name a required-looking keyword
            def configure(settings:)
            end
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/mailer.rbs")

        assert_includes contents, "def send_message: (?{ ?subject: String, ?from: String, ?urgent: bool | nil } opts) -> void"
        assert_includes contents, "def configure: (settings: { ?name: String }) -> nil"
      end
    end
  end

  def test_option_tags_do_not_apply_to_a_rest_keyword_param
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/mailer.rb", <<~RUBY)
          class Mailer
            # @param opts [Hash] options
            # @option opts [String] :subject the subject
            # @return [void]
            def send_message(**opts)
            end
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/mailer.rbs")

        assert_includes contents, "def send_message: (**untyped opts) -> void"
      end
    end
  end

  def test_explicit_ampersand_block_param_called_not_yielded_is_typed
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/runner.rb", <<~RUBY)
          class Runner
            # @yieldparam progress [Integer] percent complete
            # @yieldreturn [Boolean] whether to continue
            # @return [void]
            def run(&block)
              block.call(50)
            end
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/runner.rbs")

        assert_includes contents, "def run: () { (Integer progress) -> bool } -> void"
      end
    end
  end

  def test_explicit_ampersand_block_param_without_yieldparam_tags_does_not_crash
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/runner.rb", <<~RUBY)
          class Runner
            def run(&block)
              block.call(50)
            end
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/runner.rbs")

        RBS::Parser.parse_signature(contents)
      end
    end
  end

  def test_proc_typed_param_becomes_a_real_callable_signature
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/registry.rb", <<~RUBY)
          class Registry
            # @param callback [Proc<(Integer), void>] called with progress updates
            # @return [void]
            def register(callback)
              callback.call(50)
            end
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/registry.rbs")

        assert_includes contents, "def register: (^(Integer) -> void callback) -> void"
      end
    end
  end

  def test_attr_writer_type_is_read_from_its_writer_method
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/thing.rb", <<~RUBY)
          class Thing
            # @return [Symbol] the token
            attr_writer :token
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/thing.rbs")

        assert_includes contents, "attr_writer token: Symbol"
      end
    end
  end

  def test_strict_raises_on_an_unconvertible_yard_type
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/widget.rb", <<~RUBY)
          class Widget
            # @param name [%%%] a name
            def build(name)
              name
            end
          end
        RUBY

        error = assert_raises(Yarbs::Error) { Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true) }
        assert_match(/could not convert YARD type `%%%`/, error.message)
      end
    end
  end

  def test_deprecated_tags_become_deprecated_annotations
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/legacy.rb", <<~RUBY)
          # @deprecated Use NewLegacy instead.
          class Legacy
            # @deprecated Use #bar instead,
            #   it's faster.
            # @return [Integer]
            def foo
              1
            end

            # @deprecated
            # @return [String]
            attr_reader :name

            # @deprecated
            # @return [Integer]
            LIMIT = 3

            # @return [Integer]
            def current
              2
            end
          end
        RUBY

        Yarbs.generate(["lib/**/*.rb"], output_dir: "sig", strict: true)
        contents = File.read("sig/legacy.rbs")

        assert_includes contents, "%a{deprecated: Use NewLegacy instead.}\nclass Legacy"
        assert_includes contents, "%a{deprecated: Use #bar instead, it's faster.}\n  def foo: () -> Integer"
        assert_includes contents, "%a{deprecated}\n  attr_reader name: String"
        assert_includes contents, "%a{deprecated}\n  LIMIT: Integer"
        refute_match(/deprecated\}\n  def current/, contents)

        _, _, decls = RBS::Parser.parse_signature(contents)
        assert_equal ["deprecated"], decls.first.members.find { |m| m.is_a?(RBS::AST::Declarations::Constant) }.annotations.map(&:string)
      end
    end
  end
end
