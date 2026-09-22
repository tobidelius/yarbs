# frozen_string_literal: true

require "test_helper"

class TypeConverterTest < Minitest::Test
  def convert(*types)
    Yarbs::TypeConverter.convert(types).to_s
  end

  def test_plain_type_passes_through
    assert_equal "String", convert("String")
  end

  def test_boolean_aliases_map_to_bool
    assert_equal "bool", convert("Boolean")
    assert_equal "bool", convert("Bool")
  end

  def test_generic_angle_brackets_become_square_brackets
    assert_equal "Array[String]", convert("Array<String>")
    assert_equal "Hash[Symbol, String]", convert("Hash<Symbol, String>")
  end

  def test_hash_brace_syntax_becomes_square_brackets
    assert_equal "Hash[String, Integer]", convert("Hash{String => Integer}")
  end

  def test_multiple_types_join_as_a_union
    assert_equal "String | nil", convert("String", "nil")
  end

  def test_class_generic_becomes_singleton
    assert_equal "singleton(Foo)", convert("Class<Foo>")
  end

  def test_proc_type_becomes_a_proc_literal
    assert_equal "^(Integer) -> void", convert("Proc<(Integer), void>")
    assert_equal "^() -> void", convert("Proc<(), void>")
  end

  def test_proc_type_args_and_return_are_rewritten_recursively
    assert_equal "^(Array[String], Integer) -> bool", convert("Proc<(Array<String>, Integer), bool>")
    assert_equal "^(Integer, String) -> Hash[Symbol, String]", convert("Proc<(Integer, String), Hash<Symbol, String>>")
  end

  def test_duck_type_falls_back_to_untyped
    assert_equal "untyped", convert("#to_s")
  end

  def test_unparseable_type_falls_back_to_untyped
    _, err = capture_io { assert_equal "untyped", convert("%%%") }
    assert_match(/could not convert/, err)
  end

  def test_empty_falls_back_to_untyped
    assert_equal "untyped", Yarbs::TypeConverter.convert([]).to_s
    assert_equal "untyped", Yarbs::TypeConverter.convert(nil).to_s
  end

  def test_strict_raises_instead_of_falling_back_to_untyped
    error = assert_raises(Yarbs::Error) { Yarbs::TypeConverter.convert(["%%%"], strict: true) }
    assert_match(/could not convert YARD type `%%%`/, error.message)
  end

  def test_strict_does_not_raise_for_a_type_that_converts_cleanly
    assert_equal "String", Yarbs::TypeConverter.convert(["String"], strict: true).to_s
  end
end
