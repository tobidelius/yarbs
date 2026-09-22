# frozen_string_literal: true

require "rbs"

module Yarbs
  # Parses Ruby source into an +RBS::AST::Declarations+ tree with the
  # correct structure (arity, visibility, singleton vs. instance, etc.) but
  # every type left as +untyped+.
  #
  # This is exactly what `rbs prototype rb` does under the hood.
  module PrototypeBuilder
    # Parses Ruby source into its structural (untyped) RBS declarations.
    #
    # @param source [String] Ruby source code
    # @return [Array<RBS::AST::Declarations::t>]
    def self.build(source)
      builder = RBS::Prototype::RB.new
      builder.parse(source)
      builder.decls
    end
  end
end
