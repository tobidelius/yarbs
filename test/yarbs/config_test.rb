# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def with_config(yaml)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(".yarbs.yml", yaml) if yaml
        yield
      end
    end
  end

  def test_defaults_without_a_config_file
    with_config(nil) do
      config = Yarbs::Config.load

      assert_equal ["lib/**/*.rb"], config.paths
      assert_equal "sig", config.output
      refute config.strict
    end
  end

  def test_reads_the_config_file
    with_config("paths: [\"app/**/*.rb\"]\noutput: types\nstrict: true\n") do
      config = Yarbs::Config.load

      assert_equal ["app/**/*.rb"], config.paths
      assert_equal "types", config.output
      assert config.strict
    end
  end

  def test_the_written_config_round_trips
    with_config(Yarbs::Config.new(paths: ["lib/**/*.rb", "app/**/*.rb"]).to_yaml) do
      assert_equal ["lib/**/*.rb", "app/**/*.rb"], Yarbs::Config.load.paths
    end
  end

  def test_rejects_unknown_settings
    with_config("path: lib\n") do
      error = assert_raises(Yarbs::Error) { Yarbs::Config.load }
      assert_match(/unknown setting in \.yarbs\.yml: path/, error.message)
    end
  end

  def test_rejects_mistyped_settings
    with_config("strict: yes please\n") do
      error = assert_raises(Yarbs::Error) { Yarbs::Config.load }
      assert_match(/`strict`/, error.message)
    end
  end

  def test_rejects_invalid_yaml
    with_config("paths: [\n") do
      error = assert_raises(Yarbs::Error) { Yarbs::Config.load }
      assert_match(/could not parse/, error.message)
    end
  end
end
