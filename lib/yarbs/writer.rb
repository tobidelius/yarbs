# frozen_string_literal: true

require "rbs"

module Yarbs
  # An +RBS::Writer+ that also writes a constant's annotations, which the
  # stock writer drops (even though the RBS parser accepts +%a{...}+ on a
  # constant, and Steep reads it). Without this, a +@deprecated+ constant
  # would silently lose the +%a{deprecated}+ that {Annotator} gives it.
  class Writer < RBS::Writer
    private

    def write_decl(decl)
      return super unless decl.is_a?(RBS::AST::Declarations::Constant)

      write_comment decl.comment
      write_annotation decl.annotations
      puts "#{decl.name}: #{decl.type}"
    end
  end
end
