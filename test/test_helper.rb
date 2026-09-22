# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "yarbs"

require "tmpdir"
require "minitest/autorun"

# Some tests deliberately feed yarbs broken source files; silence YARD's own
# parser warnings for those so `rake test` output stays readable.
YARD::Logger.instance.level = Logger::FATAL
