# frozen_string_literal: true

require "test_helper"

class TestYarbs < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Yarbs::VERSION
  end

  def test_generate_returns_empty_array_when_nothing_matches
    Dir.mktmpdir do |dir|
      assert_equal [], Yarbs.generate([File.join(dir, "**", "*.rb")], output_dir: File.join(dir, "sig"))
    end
  end
end
