# frozen_string_literal: true

require "rbs"
require "yard"

module Yarbs
  # Walks an +RBS::AST::Declarations+ tree produced by {PrototypeBuilder} and
  # fills in its +untyped+ placeholders with types read from the matching
  # YARD documentation (already loaded into +YARD::Registry+).
  class Annotator
    # Fills in the +untyped+ placeholders in a decls tree using YARD documentation.
    #
    # @param decls [Array<RBS::AST::Declarations::t>]
    # @param strict [Boolean] raise instead of falling back to +untyped+
    #   when a YARD type can't be converted
    # @return [Array<RBS::AST::Declarations::t>] a new tree with YARD-derived types merged in
    def self.annotate(decls, strict: false)
      new(strict).visit_all(decls, [])
    end

    def initialize(strict)
      @strict = strict
    end

    def visit_all(decls, namespace)
      decls.map { |decl| visit(decl, namespace) }
    end

    def visit(decl, namespace)
      case decl
      when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
        inner_namespace = namespace + [decl.name.to_s]
        decl.update(members: visit_all(decl.members, inner_namespace))
      when RBS::AST::Declarations::Constant
        annotate_constant(decl, namespace)
      when RBS::AST::Members::MethodDefinition
        annotate_method(decl, namespace)
      when RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter, RBS::AST::Members::AttrAccessor
        annotate_attribute(decl, namespace)
      else
        decl
      end
    end

    private

    def annotate_constant(decl, namespace)
      yard_object = YARD::Registry.at("#{namespace.join("::")}::#{decl.name}")
      types = return_types_of(yard_object)
      return decl if types.empty?

      RBS::AST::Declarations::Constant.new(
        name: decl.name,
        type: convert(types),
        location: decl.location,
        comment: decl.comment,
        annotations: decl.annotations
      )
    end

    def annotate_method(member, namespace)
      base = namespace.join("::")
      yard_method = YARD::Registry.at("#{base}##{member.name}") || YARD::Registry.at("#{base}.#{member.name}")
      return member unless yard_method

      overloads = member.overloads.map { |overload| annotate_overload(overload, yard_method) }
      member.update(overloads: overloads)
    end

    def annotate_attribute(member, namespace)
      sep = (member.kind == :singleton) ? "." : "#"
      # attr_writer has no reader, so YARD only ever registers the `name=`
      # method (attr_accessor has both, but they share one @return tag, so
      # the reader's plain path works fine for it too).
      suffix = member.is_a?(RBS::AST::Members::AttrWriter) ? "=" : ""
      yard_attr = YARD::Registry.at("#{namespace.join("::")}#{sep}#{member.name}#{suffix}")
      types = return_types_of(yard_attr)
      return member if types.empty?

      member.update(type: convert(types))
    end

    def annotate_overload(overload, yard_method)
      method_type = overload.method_type
      new_type = method_type.update(
        type: annotate_function(method_type.type, yard_method),
        block: method_type.block && annotate_block(method_type.block, yard_method)
      )
      overload.update(method_type: new_type)
    end

    def annotate_function(function, yard_method)
      params = param_types_by_name(yard_method)
      options = option_records_by_name(yard_method)

      # @option only substitutes a record type onto a plain (non-rest) Hash
      # parameter -- for *args/**kwargs, RBS's rest type describes a single
      # element/value, and there's no way to express "these specific
      # keyword names have these specific types" through it, so @option is
      # left to apply to the base @param type there instead (see param.md).
      RBS::Types::Function.new(
        required_positionals: function.required_positionals.map { |param| annotate_param(param, params, options) },
        optional_positionals: function.optional_positionals.map { |param| annotate_param(param, params, options) },
        rest_positionals: annotate_param(function.rest_positionals, params, {}, unwrap: :array),
        trailing_positionals: function.trailing_positionals.map { |param| annotate_param(param, params, options) },
        required_keywords: annotate_keywords(function.required_keywords, params, options),
        optional_keywords: annotate_keywords(function.optional_keywords, params, options),
        rest_keywords: annotate_param(function.rest_keywords, params, {}, unwrap: :hash),
        return_type: return_type_for(function, yard_method),
        forwarding: function.forwarding
      )
    end

    def annotate_block(block, yard_method)
      yield_params = yard_method.tags(:yieldparam)
      yieldreturn = yard_method.tag(:yieldreturn)
      new_return_type = ->(current) { yieldreturn&.types&.any? ? convert(yieldreturn.types) : current }

      # `rbs prototype rb` can only infer a block's arity from literal
      # `yield x, y` call sites in the method body. A block that's only
      # ever `.call`ed (e.g. `def foo(&block); block.call(x); end`) gives
      # it nothing to go on, so it produces an `UntypedFunction` (`(?) ->
      # untyped`) instead of a full `Function` -- handle both.
      new_function = case (function = block.type)
      when RBS::Types::Function
        annotate_block_function(function, yield_params, new_return_type)
      when RBS::Types::UntypedFunction
        annotate_untyped_block_function(function, yield_params, new_return_type)
      else
        function
      end

      RBS::Types::Block.new(type: new_function, required: block.required, self_type: block.self_type)
    end

    def annotate_block_function(function, yield_params, new_return_type)
      new_required_positionals = function.required_positionals.each_with_index.map do |param, index|
        tag = yield_params[index]
        next param unless tag&.types

        RBS::Types::Function::Param.new(name: param.name || safe_symbol(tag.name), type: convert(tag.types))
      end

      RBS::Types::Function.new(
        required_positionals: new_required_positionals,
        optional_positionals: function.optional_positionals,
        rest_positionals: function.rest_positionals,
        trailing_positionals: function.trailing_positionals,
        required_keywords: function.required_keywords,
        optional_keywords: function.optional_keywords,
        rest_keywords: function.rest_keywords,
        return_type: new_return_type.call(function.return_type),
        forwarding: function.forwarding
      )
    end

    # There's no arity to preserve here, but if `@yieldparam` tags exist we
    # at least know the documented shape, so build a full positional-only
    # `Function` from them instead of leaving the block's params untyped.
    def annotate_untyped_block_function(function, yield_params, new_return_type)
      return function.map_type { new_return_type.call(function.return_type) } if yield_params.empty?

      positionals = yield_params.map do |tag|
        RBS::Types::Function::Param.new(name: safe_symbol(tag.name), type: convert(tag.types))
      end

      RBS::Types::Function.new(
        required_positionals: positionals,
        optional_positionals: [],
        rest_positionals: nil,
        trailing_positionals: [],
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil,
        return_type: new_return_type.call(function.return_type),
        forwarding: nil
      )
    end

    # Applies the type documented for a single structural parameter.
    #
    # @param unwrap [Symbol, nil] for a rest parameter (`*args`/`**kwargs`),
    #   YARD conventionally documents the *collected* type (`Array<String>`,
    #   `Hash{Symbol => String}`), but RBS's `*`/`**` types describe a single
    #   element instead, so one layer of `Array`/`Hash` is stripped back off.
    def annotate_param(param, params, options, unwrap: nil)
      return param unless param&.name

      name = param.name.to_s
      return param.map_type { options[name] } if options[name]

      types = params[name]
      types ? param.map_type { unwrap_rest_type(convert(types), unwrap) } : param
    end

    def unwrap_rest_type(type, unwrap)
      return type unless type.is_a?(RBS::Types::ClassInstance)

      case unwrap
      when :array
        type.args.first if type.name.to_s == "Array" && type.args.size == 1
      when :hash
        type.args.last if type.name.to_s == "Hash" && type.args.size == 2
      end || type
    end

    def annotate_keywords(keywords, params, options)
      keywords.each_with_object({}) do |(key, param), result|
        name = key.to_s

        if options[name]
          result[key] = param.map_type { options[name] }
          next
        end

        types = params[name]
        result[key] = types ? param.map_type { convert(types) } : param
      end
    end

    def param_types_by_name(yard_method)
      yard_method.tags(:param).each_with_object({}) do |tag, result|
        next unless tag.name && tag.types

        result[tag.name.to_s.sub(/\A[*&]+/, "")] = tag.types
      end
    end

    # Builds an `RBS::Types::Record` (`{ key: Type, ?key2: Type2 }`) for each
    # parameter documented with YARD `@option` tags, keyed by that
    # parameter's name.
    #
    # e.g. `@option opts [String] :subject` contributes a `:subject` field
    # to the record built for the `opts` parameter. Every field is
    # optional, since that's what an options hash means: you're never
    # required to pass any particular key.
    def option_records_by_name(yard_method)
      groups = yard_method.tags(:option).group_by { |tag| tag.name.to_s }

      groups.filter_map do |name, tags|
        fields = tags.each_with_object({}) do |tag, result|
          pair = tag.pair
          next unless pair&.name

          key = pair.name.to_s.sub(/\A:/, "").to_sym
          result[key] = [convert(pair.types), false]
        end

        [name, RBS::Types::Record.new(all_fields: fields, location: nil)] unless fields.empty?
      end.to_h
    end

    def return_type_for(function, yard_method)
      return function.return_type if yard_method.name == :initialize && yard_method.scope == :instance

      types = return_types_of(yard_method)
      types.empty? ? function.return_type : convert(types)
    end

    def return_types_of(yard_object)
      return [] unless yard_object

      yard_object.tags(:return).flat_map { |tag| tag.types || [] }
    end

    def convert(types)
      TypeConverter.convert(types, strict: @strict)
    end

    def safe_symbol(name)
      (name.nil? || name.empty?) ? nil : name.to_sym
    end
  end
end
