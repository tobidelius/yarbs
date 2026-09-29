# frozen_string_literal: true

require "test_helper"

class WatcherTest < Minitest::Test
  def base_directory(pattern)
    Yarbs::Watcher.base_directory(pattern)
  end

  def test_base_directory_strips_the_glob_portion
    assert_equal "lib", base_directory("lib/**/*.rb")
    assert_equal "app", base_directory("app/**/*rb")
    assert_equal "lib", base_directory("lib/foo*.rb")
    assert_equal ".", base_directory("*.rb")
  end

  def test_base_directory_of_a_literal_path_is_its_dirname
    assert_equal "lib", base_directory("lib/widget.rb")
  end

  def test_matches_patterns_uses_fnmatch_semantics
    watcher = Yarbs::Watcher.new(["lib/**/*.rb"], output_dir: "sig")

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        assert watcher.send(:matches_patterns?, File.join(dir, "lib/foo/bar.rb"))
        refute watcher.send(:matches_patterns?, File.join(dir, "sig/foo.rbs"))
      end
    end
  end
end
