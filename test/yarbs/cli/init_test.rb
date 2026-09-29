# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"

class CLIInitTest < Minitest::Test
  def run_init(**options)
    out = StringIO.new
    Yarbs::CLI::Init.run(install: false, out: out, **options)
    out.string
  end

  def in_project
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(["lib", ".git"])
        File.write("lib/greeter.rb", "class Greeter\n  # @return [String]\n  def greet = \"hi\"\nend\n")
        yield
      end
    end
  end

  def test_creates_every_file_and_generates_signatures
    in_project do
      output = run_init

      assert_match(/create  \.yarbs\.yml/, output)
      assert_match(/create  Steepfile/, output)
      assert_match(/create  rbs_collection\.yaml/, output)
      assert_match(/create  \.gitignore \(added \/\.gem_rbs_collection\/\)/, output)
      assert_match(/wrote  1 file to sig\//, output)

      assert_equal ["lib/**/*.rb"], Yarbs::Config.load.paths
      assert_includes File.read("Steepfile"), %(check "lib")
      assert_includes File.read("sig/greeter.rbs"), "def greet: () -> String"
    end
  end

  def test_never_overwrites_existing_files
    in_project do
      File.write("Steepfile", "# mine\n")
      File.write("rbs_collection.yaml", "# mine\n")
      File.write(".yarbs.yml", "paths: [\"lib/**/*.rb\"]\n")

      output = run_init

      assert_match(/skip  Steepfile \(already exists\)/, output)
      assert_match(/skip  rbs_collection\.yaml \(already exists\)/, output)
      assert_match(/skip  \.yarbs\.yml \(already exists\)/, output)
      assert_equal "# mine\n", File.read("Steepfile")
      assert_equal "# mine\n", File.read("rbs_collection.yaml")
    end
  end

  def test_an_existing_config_wins_over_the_given_paths
    in_project do
      FileUtils.mkdir_p("src")
      File.write(".yarbs.yml", "paths: [\"src/**/*.rb\"]\n")

      run_init(paths: ["lib/**/*.rb"])

      assert_includes File.read("Steepfile"), %(check "src")
    end
  end

  def test_only_adds_the_missing_gitignore_entries
    in_project do
      File.write("yarbs.gemspec", "")
      File.write(".gitignore", "/pkg/\n.gem_rbs_collection")

      output = run_init

      assert_match(/update  \.gitignore \(added \/rbs_collection\.lock\.yaml\)/, output)
      assert_equal "/pkg/\n.gem_rbs_collection\n/rbs_collection.lock.yaml\n", File.read(".gitignore")

      assert_match(/skip  \.gitignore \(already has yarbs' entries\)/, run_init)
    end
  end

  def test_an_app_commits_its_rbs_collection_lock
    in_project do
      run_init

      refute_includes File.read(".gitignore"), "rbs_collection.lock.yaml"
    end
  end

  def test_leaves_gitignore_alone_outside_a_git_repository
    in_project do
      FileUtils.rm_rf(".git")

      assert_match(/skip  \.gitignore \(not a git repository\)/, run_init)
      refute File.exist?(".gitignore")
    end
  end

  def test_dry_run_writes_nothing
    in_project do
      output = run_init(dry_run: true)

      assert_match(/create  Steepfile/, output)
      assert_equal %w[.git lib], Dir.children(".").sort
    end
  end
end
