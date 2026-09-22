# frozen_string_literal: true

require "rbs"

module Yarbs
  # Converts YARD type strings (e.g. "Array<String>", "Boolean") into RBS
  # types, falling back to +untyped+ for anything that doesn't map cleanly.
  module TypeConverter
    UNTYPED = RBS::Types::Bases::Any.new(location: nil)

    # Converts a YARD tag's type list into a single RBS type.
    #
    # @param yard_types [Array<String>, nil] the raw strings from a YARD
    #   tag's +types+ (e.g. +["String", "nil"]+ for +@param [String, nil]+)
    # @param strict [Boolean] raise instead of falling back to +untyped+
    #   when a type can't be converted
    # @return [RBS::Types::t] the best matching RBS type, or +untyped+
    def self.convert(yard_types, strict: false)
      return UNTYPED if yard_types.nil? || yard_types.empty?

      source = yard_types.map { |type| rewrite(type) }.join(" | ")

      begin
        RBS::Parser.parse_type(source, require_eof: true) || UNTYPED
      rescue RBS::ParsingError => e
        message = "yarbs: could not convert YARD type `#{yard_types.join(", ")}` to RBS (#{e.message})"
        raise Error, message if strict

        warn "#{message}; using untyped"
        UNTYPED
      end
    end

    # `Proc<(ArgType, ...), ReturnType>` -> `^(ArgType, ...) -> ReturnType`,
    # RBS's proc-literal type (a real, typed callable signature).
    #
    # YARD's own tag parser mangles a literal `->` written inside
    # `@param [...]` brackets, so this convention avoids the arrow entirely.
    PROC_TYPE = /\AProc<\((?<args>.*)\),\s*(?<return_type>.+)>\z/m
    private_constant :PROC_TYPE

    # Rewrites a single YARD type string into RBS syntax, best-effort.
    #
    # @param type [String] a single YARD type string
    # @return [String] the same type rewritten using RBS syntax, best-effort
    def self.rewrite(type)
      type = type.strip
      return "untyped" if type.start_with?("#")

      if (match = PROC_TYPE.match(type))
        args = split_top_level(match[:args]).map { |arg| rewrite(arg) }
        return "^(#{args.join(", ")}) -> #{rewrite(match[:return_type])}"
      end

      type = type.gsub(/\bBool(?:ean)?\b/, "bool")
      type = type.gsub(/\bClass<(.+)>/) { "singleton(#{Regexp.last_match(1)})" }
      type = type.gsub(/\bHash\{\s*(.+?)\s*=>\s*(.+?)\s*\}/m) { "Hash[#{Regexp.last_match(1)}, #{Regexp.last_match(2)}]" }
      type.tr("<>", "[]")
    end
    private_class_method :rewrite

    # Splits on top-level commas only, respecting `<>`/`{}`/`()`/`[]`
    # nesting, so e.g. `Array<String>, Integer` splits into two, not three.
    #
    # @param str [String]
    # @return [Array<String>]
    def self.split_top_level(str)
      return [] if str.strip.empty?

      depth = 0
      parts = []
      current = +""

      str.each_char do |char|
        case char
        when "<", "{", "(", "["
          depth += 1
          current << char
        when ">", "}", ")", "]"
          depth -= 1
          current << char
        when ","
          if depth.zero?
            parts << current.strip
            current = +""
          else
            current << char
          end
        else
          current << char
        end
      end

      parts << current.strip
    end
    private_class_method :split_top_level
  end
end
