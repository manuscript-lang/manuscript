[Wiki](../index.md) › [LLVM LangRef](index.md)

# Metadata

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="metadata"></a>

<a id="id8"></a>

## Metadata

LLVM IR allows metadata to be attached to instructions and global objects in the program that can convey extra information about the code to the optimizers and code generator.

There are two metadata primitives: strings and nodes. There are also specialized nodes which have a distinguished name and a set of named arguments.

Note

One example application of metadata is source-level debug information, which is currently the only user of specialized nodes.

Metadata does not have a type, and is not a value.

A value of non-`metadata` type can be used in a metadata context using the syntax ‘`<type> <value>`’.

All other metadata is identified in syntax as starting with an exclamation point (’`!`’).

Metadata may be used in the following value contexts by using the `metadata` type:

- Arguments to certain intrinsic functions, as described in their specification.

- Arguments to the `catchpad`/`cleanuppad` instructions.

Note

Metadata can be “wrapped” in a `MetadataAsValue` so it can be referenced in a value context: `MetadataAsValue` is-a `Value`.

A typed value can be “wrapped” in `ValueAsMetadata` so it can be referenced in a metadata context: `ValueAsMetadata` is-a `Metadata`.

There is no explicit syntax for a `ValueAsMetadata`, and instead the fact that a type identifier cannot begin with an exclamation point is used to resolve ambiguity.

A `metadata` type implies a `MetadataAsValue`, and when followed with a ‘`<type> <value>`’ pair it wraps the typed value in a `ValueAsMetadata`.

For example, the first argument to this call is a `MetadataAsValue(ValueAsMetadata(Value))`:

    call void @llvm.foo(metadata i32 1)

Whereas the first argument to this call is a `MetadataAsValue(MDNode)`:

    call void @llvm.foo(metadata !0)

The first element of this `MDTuple` is a `MDNode`:

    !{!0}

And the first element of this `MDTuple` is a `ValueAsMetadata(Value)`:

    !{i32 1}

<a id="metadata-strings-mdstring"></a>

<a id="metadata-string"></a>

### Metadata Strings (`MDString`)

A metadata string is a string surrounded by double quotes. It can contain any character by escaping non-printable characters with “`\xx`” where “`xx`” is the two digit hex code. For example: “`!"test\00"`”.

Note

A metadata string is metadata, but is not a metadata node.

<a id="metadata-nodes-mdnode"></a>

<a id="metadata-node"></a>

### Metadata Nodes (`MDNode`)

Metadata tuples are represented with notation similar to structure constants: a comma separated list of elements, surrounded by braces and preceded by an exclamation point. Metadata nodes can have any values as their operand. For example:

    !{!"test\00", i32 10}

Metadata nodes that aren’t uniqued use the `distinct` keyword. For example:

    !0 = distinct !{!"test\00", i32 10}

`distinct` nodes are useful when nodes shouldn’t be merged based on their content. They can also occur when transformations cause uniquing collisions when metadata operands change.

A [named metadata](high-level-structure.md#namedmetadatastructure) is a collection of metadata nodes, which can be looked up in the module symbol table. For example:

    !foo = !{!4, !3}

Metadata can be used as function arguments. Here the `llvm.dbg.value` intrinsic is using three metadata arguments:

    call void @llvm.dbg.value(metadata !24, metadata !25, metadata !26)

Metadata can be attached to an instruction. Here metadata `!21` is attached to the `add` instruction using the `!dbg` identifier:

    %indvar.next = add i64 %indvar, 1, !dbg !21

Instructions may not have multiple metadata attachments with the same identifier.

Metadata can also be attached to a function or a global variable. Here metadata `!22` is attached to the `f1` and `f2` functions, and the globals `g1` and `g2` using the `!dbg` identifier:

    declare !dbg !22 void @f1()
    define void @f2() !dbg !22 {
      ret void
    }

    @g1 = global i32 0, !dbg !22
    @g2 = external global i32, !dbg !22

Unlike instructions, global objects (functions and global variables) may have multiple metadata attachments with the same identifier.

A transformation is required to drop any metadata attachment that it does not recognize or cannot preserve. Currently there is an exception for metadata attachment to globals for `!func_sanitize`, `!type`, `!absolute_symbol`, `!implicit.ref` and `!associated` which can’t be unconditionally dropped unless the global is itself deleted.

Metadata attached to a module using named metadata may not be dropped, with the exception of debug metadata (named metadata with the name `!llvm.dbg.*`).

More information about specific metadata nodes recognized by the optimizers and code generator is found below.

<a id="specialized-metadata-nodes"></a>

<a id="specialized-metadata"></a>

#### Specialized Metadata Nodes

Specialized metadata nodes are custom data structures in metadata (as opposed to generic tuples). Their fields are labelled, and can be specified in any order.

These aren’t inherently debug info centric, but currently all the specialized metadata nodes are related to debug info.

<a id="dicompileunit"></a>

<a id="id9"></a>

##### DICompileUnit

`DICompileUnit` nodes represent a compile unit. The `enums:`, `retainedTypes:`, `globals:`, `imports:` and `macros:` fields are tuples containing the debug info to be emitted along with the compile unit, regardless of code optimizations (some nodes are only emitted if there are references to them from instructions). The `debugInfoForProfiling:` field is a boolean indicating whether or not line-table discriminators are updated to provide more-accurate debug info for profiling results.

    !0 = !DICompileUnit(language: DW_LANG_C99, file: !1, producer: "clang",
                        isOptimized: true, flags: "-O2", runtimeVersion: 2,
                        splitDebugFilename: "abc.debug", emissionKind: FullDebug,
                        enums: !2, retainedTypes: !3, globals: !4, imports: !5,
                        macros: !6, dwoId: 0x0abcd)

The optional `dialect:` field encodes the source-language *dialect* of the compile unit as an enum. It corresponds to the `DW_AT_LLVM_language_dialect` attribute emitted on `DW_TAG_compile_unit` and is intended for language dialects that represent different execution models. When specified, the field must name one of the known dialects, either symbolically or with the matching numeric value; see [LLVM Language Dialect](SourceLevelDebugging.html#llvm-language-dialect) for the list of supported values.

Omitting the `dialect:` field is the only way to express “no dialect” in textual IR.

    !0 = !DICompileUnit(language: DW_LANG_C_plus_plus, file: !1, producer: "clang",
                        isOptimized: false, runtimeVersion: 0,
                        emissionKind: FullDebug,
                        dialect: DW_LLVM_LANG_DIALECT_simt)

Compile unit descriptors provide the root scope for objects declared in a specific compilation unit. File descriptors are defined using this scope. These descriptors are collected by a named metadata node `!llvm.dbg.cu`. They keep track of global variables, type information, and imported entities (declarations and namespaces).

<a id="difile"></a>

<a id="id10"></a>

##### DIFile

`DIFile` nodes represent files. The `filename:` can include slashes.

    !0 = !DIFile(filename: "path/to/file", directory: "/path/to/dir",
                 checksumkind: CSK_MD5,
                 checksum: "000102030405060708090a0b0c0d0e0f")

Files are sometimes used in `scope:` fields, and are the only valid target for `file:` fields.

The `checksum:` and `checksumkind:` fields are optional. If one of these fields is present, then the other is required to be present as well. Valid values for `checksumkind:` field are: {CSK_MD5, CSK_SHA1, CSK_SHA256}

<a id="dibasictype"></a>

<a id="id11"></a>

##### DIBasicType

`DIBasicType` nodes represent primitive types, such as `int`, `bool` and `float`. `tag:` defaults to `DW_TAG_base_type`.

    !0 = !DIBasicType(name: "unsigned char", size: 8, align: 8,
                      encoding: DW_ATE_unsigned_char)
    !1 = !DIBasicType(tag: DW_TAG_unspecified_type, name: "decltype(nullptr)")

The `encoding:` describes the details of the type. Usually it’s one of the following:

    DW_ATE_address       = 1
    DW_ATE_boolean       = 2
    DW_ATE_float         = 4
    DW_ATE_signed        = 5
    DW_ATE_signed_char   = 6
    DW_ATE_unsigned      = 7
    DW_ATE_unsigned_char = 8

<a id="difixedpointtype"></a>

<a id="id12"></a>

##### DIFixedPointType

`DIFixedPointType` nodes represent fixed-point types. A fixed-point type is conceptually an integer with a scale factor. `DIFixedPointType` is derived from `DIBasicType` and inherits its attributes. However, only certain encodings are accepted:

    DW_ATE_signed_fixed   = 13
    DW_ATE_unsigned_fixed = 14

There are three kinds of fixed-point type: binary, where the scale factor is a power of 2; decimal, where the scale factor is a power of 10; and rational, where the scale factor is an arbitrary rational number.

    !0 = !DIFixedPointType(name: "decimal", size: 8, encoding: DW_ATE_signed_fixed,
                           kind: Decimal, factor: -4)
    !1 = !DIFixedPointType(name: "binary", size: 8, encoding: DW_ATE_unsigned_fixed,
                           kind: Binary, factor: -16)
    !2 = !DIFixedPointType(name: "rational", size: 8, encoding: DW_ATE_signed_fixed,
                           kind: Rational, numerator: 1234, denominator: 5678)

<a id="disubroutinetype"></a>

<a id="id13"></a>

##### DISubroutineType

`DISubroutineType` nodes represent subroutine types. Their `types:` field refers to a tuple; the first operand is the return type, while the rest are the types of the formal arguments in order. If the first operand is `null`, that represents a function with no return value (such as `void foo() {}` in C++).

    !0 = !BasicType(name: "int", size: 32, align: 32, DW_ATE_signed)
    !1 = !BasicType(name: "char", size: 8, align: 8, DW_ATE_signed_char)
    !2 = !DISubroutineType(types: !{null, !0, !1}) ; void (int, char)

<a id="diderivedtype"></a>

<a id="id14"></a>

##### DIDerivedType

`DIDerivedType` nodes represent types derived from other types, such as qualified types.

    !0 = !DIBasicType(name: "unsigned char", size: 8, align: 8,
                      encoding: DW_ATE_unsigned_char)
    !1 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !0, size: 32,
                        align: 32)

The following `tag:` values are valid:

    DW_TAG_member             = 13
    DW_TAG_pointer_type       = 15
    DW_TAG_reference_type     = 16
    DW_TAG_typedef            = 22
    DW_TAG_inheritance        = 28
    DW_TAG_ptr_to_member_type = 31
    DW_TAG_const_type         = 38
    DW_TAG_friend             = 42
    DW_TAG_volatile_type      = 53
    DW_TAG_restrict_type      = 55
    DW_TAG_atomic_type        = 71
    DW_TAG_immutable_type     = 75

`DW_TAG_member` is used to define a member of a [composite type](#dicompositetype). The type of the member is the `baseType:`. The `offset:` is the member’s bit offset. If the composite type has an ODR `identifier:` and does not set `flags: DIFwdDecl`, then the member is uniqued based only on its `name:` and `scope:`.

`DW_TAG_inheritance` and `DW_TAG_friend` are used in the `elements:` field of [composite types](#dicompositetype) to describe parents and friends.

`DW_TAG_typedef` is used to provide a name for the `baseType:`.

`DW_TAG_pointer_type`, `DW_TAG_reference_type`, `DW_TAG_const_type`, `DW_TAG_volatile_type`, `DW_TAG_restrict_type`, `DW_TAG_atomic_type` and `DW_TAG_immutable_type` are used to qualify the `baseType:`.

Note that the `void *` type is expressed as a type derived from NULL.

<a id="dicompositetype"></a>

<a id="id15"></a>

##### DICompositeType

`DICompositeType` nodes represent types composed of other types, like structures and unions. `elements:` points to a tuple of the composed types.

If the source language supports ODR, the `identifier:` field gives the unique identifier used for type merging between modules. When specified, [subprogram declarations](#disubprogramdeclaration) and [member derived types](#diderivedtypemember) that reference the ODR-type in their `scope:` change uniquing rules.

For a given `identifier:`, there should only be a single composite type that does not have `flags: DIFlagFwdDecl` set. LLVM tools that link modules together will unique such definitions at parse time via the `identifier:` field, even if the nodes are `distinct`.

    !0 = !DIEnumerator(name: "SixKind", value: 7)
    !1 = !DIEnumerator(name: "SevenKind", value: 7)
    !2 = !DIEnumerator(name: "NegEightKind", value: -8)
    !3 = !DICompositeType(tag: DW_TAG_enumeration_type, name: "Enum", file: !12,
                          line: 2, size: 32, align: 32, identifier: "_M4Enum",
                          elements: !{!0, !1, !2})

The following `tag:` values are valid:

    DW_TAG_array_type       = 1
    DW_TAG_class_type       = 2
    DW_TAG_enumeration_type = 4
    DW_TAG_structure_type   = 19
    DW_TAG_union_type       = 23
    DW_TAG_variant          = 25
    DW_TAG_variant_part     = 51

For `DW_TAG_array_type`, the `elements:` should be [subrange descriptors](#disubrange) or [subrange descriptors](#disubrangetype), each representing the range of subscripts at that level of indexing. The `DIFlagVector` flag to `flags:` indicates that an array type is a native packed vector. The optional `dataLocation` is a `DIExpression` that describes how to get from an object’s address to the actual raw data, if they aren’t equivalent. This is only supported for array types, particularly to describe Fortran arrays, which have an array descriptor in addition to the array data. Alternatively it can also be `DIVariable` which has the address of the actual raw data. The Fortran language supports pointer arrays which can be attached to actual arrays, this attachment between pointer and pointee is called association. The optional `associated` is a `DIExpression` that describes whether the pointer array is currently associated. The optional `allocated` is a `DIExpression` that describes whether the allocatable array is currently allocated. The optional `rank` is a `DIExpression` that describes the rank (number of dimensions) of Fortran assumed rank array (rank is known at runtime). The optional `bitStride` is an unsigned constant that describes the number of bits occupied by an element of the array; this is only needed if it differs from the element type’s natural size, and is normally used for packed arrays.

For `DW_TAG_enumeration_type`, the `elements:` should be [enumerator descriptors](#dienumerator), each representing the definition of an enumeration value for the set. All enumeration type descriptors are collected in the `enums:` field of the [compile unit](#dicompileunit).

For `DW_TAG_structure_type`, `DW_TAG_class_type`, and `DW_TAG_union_type`, the `elements:` should be [derived types](#diderivedtype) with `tag: DW_TAG_member`, `tag: DW_TAG_inheritance`, or `tag: DW_TAG_friend`; or [subprograms](#disubprogram) with `isDefinition: false`.

`DW_TAG_variant_part` introduces a variant part of a structure type. This should have a discriminant, a member that is used to decide which elements are active. The elements of the variant part should each be a `DW_TAG_member`; if a member has a non-null `ExtraData`, then it is a `ConstantInt` or `ConstantDataArray` indicating the values of the discriminant member that cause the activation of this branch. A member itself may be of composite type with tag `DW_TAG_variant`; in this case the members of that composite type are inlined into the current one.

<a id="disubrange"></a>

<a id="id16"></a>

##### DISubrange

`DISubrange` nodes are the elements for `DW_TAG_array_type` variants of [DICompositeType](#dicompositetype).

- `count: -1` indicates an empty array.

- `count: !10` describes the count with a [DILocalVariable](#dilocalvariable).

- `count: !12` describes the count with a [DIGlobalVariable](#diglobalvariable).

    !0 = !DISubrange(count: 5, lowerBound: 0) ; array counting from 0
    !1 = !DISubrange(count: 5, lowerBound: 1) ; array counting from 1
    !2 = !DISubrange(count: -1) ; empty array.

    ; Scopes used in rest of example
    !6 = !DIFile(filename: "vla.c", directory: "/path/to/file")
    !7 = distinct !DICompileUnit(language: DW_LANG_C99, file: !6)
    !8 = distinct !DISubprogram(name: "foo", scope: !7, file: !6, line: 5)

    ; Use of local variable as count value
    !9 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
    !10 = !DILocalVariable(name: "count", scope: !8, file: !6, line: 42, type: !9)
    !11 = !DISubrange(count: !10, lowerBound: 0)

    ; Use of global variable as count value
    !12 = !DIGlobalVariable(name: "count", scope: !8, file: !6, line: 22, type: !9)
    !13 = !DISubrange(count: !12, lowerBound: 0)

<a id="disubrangetype"></a>

<a id="id17"></a>

##### DISubrangeType

`DISubrangeType` is similar to `DISubrange`, but it is also a `DIType`. It may be used as the type of an object, but could also be used as an array index.

Like `DISubrange`, it can hold a lower bound and count, or a lower bound and upper bound. A `DISubrangeType` refers to the underlying type of which it is a subrange; this type can be an integer type or an enumeration type.

A `DISubrangeType` may also have a stride – unlike `DISubrange`, this stride is a bit stride. The stride is only useful when a `DISubrangeType` is used as an array index type.

Finally, `DISubrangeType` may have a bias. In Ada, a program can request that a subrange value be stored in the minimum number of bits required. In this situation, the stored value is biased by the lower bound – e.g., a range `-7 .. 0` may take 3 bits in memory, and the value -5 would be stored as 2 (a bias of -7).

    ; Scopes used in rest of example
    !0 = !DIFile(filename: "vla.c", directory: "/path/to/file")
    !1 = distinct !DICompileUnit(language: DW_LANG_C99, file: !0)
    !2 = distinct !DISubprogram(name: "foo", scope: !1, file: !0, line: 5)

    ; Base type used in example.
    !3 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)

    ; A simple subrange with a name.
    !4 = !DISubrange(name: "subrange", file: !0, line: 17, size: 32,
                     align: 32, baseType: !3, lowerBound: 18, count: 12)
    ; A subrange with a bias.
    !5 = !DISubrange(name: "biased", lowerBound: -7, upperBound: 0,
                     bias: -7, size: 3)
    ; A subrange with a bit stride.
    !6 = !DISubrange(name: "biased", lowerBound: 0, upperBound: 7,
                     stride: 3)

<a id="dienumerator"></a>

<a id="id18"></a>

##### DIEnumerator

`DIEnumerator` nodes are the elements for `DW_TAG_enumeration_type` variants of [DICompositeType](#dicompositetype).

    !0 = !DIEnumerator(name: "SixKind", value: 7)
    !1 = !DIEnumerator(name: "SevenKind", value: 7)
    !2 = !DIEnumerator(name: "NegEightKind", value: -8)

<a id="ditemplatetypeparameter"></a>

##### DITemplateTypeParameter

`DITemplateTypeParameter` nodes represent type parameters to generic source language constructs. They are used (optionally) in [DICompositeType](#dicompositetype) and [DISubprogram](#disubprogram) `templateParams:` fields.

    !0 = !DITemplateTypeParameter(name: "Ty", type: !1)

<a id="ditemplatevalueparameter"></a>

##### DITemplateValueParameter

`DITemplateValueParameter` nodes represent value parameters to generic source language constructs. `tag:` defaults to `DW_TAG_template_value_parameter`, but if specified can also be set to `DW_TAG_GNU_template_template_param` or `DW_TAG_GNU_template_param_pack`. They are used (optionally) in [DICompositeType](#dicompositetype) and [DISubprogram](#disubprogram) `templateParams:` fields.

    !0 = !DITemplateValueParameter(name: "Ty", type: !1, value: i32 7)

<a id="dinamespace"></a>

##### DINamespace

`DINamespace` nodes represent namespaces in the source language.

    !0 = !DINamespace(name: "myawesomeproject", scope: !1, file: !2, line: 7)

<a id="diglobalvariable"></a>

<a id="id19"></a>

##### DIGlobalVariable

`DIGlobalVariable` nodes represent global variables in the source language.

    @foo = global i32, !dbg !0
    !0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
    !1 = !DIGlobalVariable(name: "foo", linkageName: "foo", scope: !2,
                           file: !3, line: 7, type: !4, isLocal: true,
                           isDefinition: false, declaration: !5)

<a id="diglobalvariableexpression"></a>

##### DIGlobalVariableExpression

`DIGlobalVariableExpression` nodes tie a [DIGlobalVariable](#diglobalvariable) together with a [DIExpression](SourceLevelDebugging.html#diexpression).

    @lower = global i32, !dbg !0
    @upper = global i32, !dbg !1
    !0 = !DIGlobalVariableExpression(
             var: !2,
             expr: !DIExpression(DW_OP_LLVM_fragment, 0, 32)
             )
    !1 = !DIGlobalVariableExpression(
             var: !2,
             expr: !DIExpression(DW_OP_LLVM_fragment, 32, 32)
             )
    !2 = !DIGlobalVariable(name: "split64", linkageName: "split64", scope: !3,
                           file: !4, line: 8, type: !5, declaration: !6)

All global variable expressions should be referenced by the `globals:` field of a [compile unit](#dicompileunit).

<a id="disubprogram"></a>

<a id="id20"></a>

##### DISubprogram

`DISubprogram` nodes represent functions from the source language. A distinct `DISubprogram` may be attached to a function definition using `!dbg` metadata. A unique `DISubprogram` may be attached to a function declaration used for call site debug info. The `retainedNodes:` field is a list of [variables](#dilocalvariable) and [labels](#dilabel) that must be retained, even if their IR counterparts are optimized out of the IR. The `type:` field must point at an [DISubroutineType](#disubroutinetype).

When `spFlags: DISPFlagDefinition` is not present, subprograms describe a declaration in the type tree as opposed to a definition of a function. In this case, the `declaration` field must be empty. If the scope is a composite type with an ODR `identifier:` and that does not set `flags: DIFwdDecl`, then the subprogram declaration is uniqued based only on its `linkageName:` and `scope:`.

    define void @_Z3foov() !dbg !0 {
      ...
    }

    !0 = distinct !DISubprogram(name: "foo", linkageName: "_Zfoov", scope: !1,
                                file: !2, line: 7, type: !3,
                                spFlags: DISPFlagDefinition | DISPFlagLocalToUnit,
                                scopeLine: 8, containingType: !4,
                                virtuality: DW_VIRTUALITY_pure_virtual,
                                virtualIndex: 10, flags: DIFlagPrototyped,
                                isOptimized: true, unit: !5, templateParams: !6,
                                declaration: !7, retainedNodes: !8,
                                thrownTypes: !9)

<a id="dilexicalblock"></a>

<a id="id21"></a>

##### DILexicalBlock

`DILexicalBlock` nodes describe nested blocks within a [subprogram](#disubprogram). The line number and column numbers are used to distinguish two lexical blocks at same depth. They are valid targets for `scope:` fields.

    !0 = distinct !DILexicalBlock(scope: !1, file: !2, line: 7, column: 35)

Usually lexical blocks are `distinct` to prevent node merging based on operands.

<a id="dilexicalblockfile"></a>

<a id="id22"></a>

##### DILexicalBlockFile

`DILexicalBlockFile` nodes are used to discriminate between sections of a [lexical block](#dilexicalblock). The `file:` field can be changed to indicate textual inclusion, or the `discriminator:` field can be used to discriminate between control flow within a single block in the source language.

    !0 = !DILexicalBlock(scope: !3, file: !4, line: 7, column: 35)
    !1 = !DILexicalBlockFile(scope: !0, file: !4, discriminator: 0)
    !2 = !DILexicalBlockFile(scope: !0, file: !4, discriminator: 1)

<a id="dilocation"></a>

<a id="id23"></a>

##### DILocation

`DILocation` nodes represent source debug locations. The `scope:` field is mandatory, and points at an [DILexicalBlockFile](#dilexicalblockfile), an [DILexicalBlock](#dilexicalblock), or an [DISubprogram](#disubprogram).

    !0 = !DILocation(line: 2900, column: 42, scope: !1, inlinedAt: !2)

<a id="dilocalvariable"></a>

<a id="id24"></a>

##### DILocalVariable

`DILocalVariable` nodes represent local variables in the source language. If the `arg:` field is set to non-zero, then this variable is a subprogram parameter, and it will be included in the `retainedNodes:` field of its [DISubprogram](#disubprogram).

    !0 = !DILocalVariable(name: "this", arg: 1, scope: !3, file: !2, line: 7,
                          type: !3, flags: DIFlagArtificial)
    !1 = !DILocalVariable(name: "x", arg: 2, scope: !4, file: !2, line: 7,
                          type: !3)
    !2 = !DILocalVariable(name: "y", scope: !5, file: !2, line: 7, type: !3)

<a id="diexpression"></a>

##### DIExpression

`DIExpression` nodes represent expressions that are inspired by the DWARF expression language. They are used in [debug records](SourceLevelDebugging.html#debug-records) (such as `#dbg_declare` and `#dbg_value`) to describe how the referenced LLVM variable relates to the source language variable.

See [DIExpression](SourceLevelDebugging.html#diexpression) for details.

Note

`DIExpression`s are always printed and parsed inline; they can never be referenced by an ID (e.g., `!1`).

Some examples of expressions:

    !DIExpression(DW_OP_deref)
    !DIExpression(DW_OP_plus_uconst, 3)
    !DIExpression(DW_OP_constu, 3, DW_OP_plus)
    !DIExpression(DW_OP_bit_piece, 3, 7)
    !DIExpression(DW_OP_deref, DW_OP_constu, 3, DW_OP_plus, DW_OP_LLVM_fragment, 3, 7)
    !DIExpression(DW_OP_constu, 2, DW_OP_swap, DW_OP_xderef)
    !DIExpression(DW_OP_constu, 42, DW_OP_stack_value)

<a id="diassignid"></a>

##### DIAssignID

`DIAssignID` nodes have no operands and are always distinct. They are used to link together ([#dbg_assign records](instructions-vector-aggregate.md#debugrecords)) and instructions that store in IR. See [Debug Info Assignment Tracking](AssignmentTracking.html) for more info.

    store i32 %a, ptr %a.addr, align 4, !DIAssignID !2
    #dbg_assign(%a, !1, !DIExpression(), !2, %a.addr, !DIExpression(), !3)

    !2 = distinct !DIAssignID()

<a id="diarglist"></a>

##### DIArgList

`DIArgList` nodes hold a list of constant or SSA value references. These are used in [debug records](instructions-vector-aggregate.md#debugrecords) in combination with a `DIExpression` that uses the `DW_OP_LLVM_arg` operator. Because a `DIArgList` may refer to local values within a function, it must only be used as a function argument, must always be inlined, and cannot appear in named metadata.

    #dbg_value(!DIArgList(i32 %a, i32 %b),
               !16,
               !DIExpression(DW_OP_LLVM_arg, 0, DW_OP_LLVM_arg, 1, DW_OP_plus),
               !26)

<a id="diflags"></a>

##### DIFlags

These flags encode various properties of DINodes.

The `ExportSymbols` flag marks a class, struct or union whose members may be referenced as if they were defined in the containing class or union. This flag is used to decide whether the `DW_AT_export_symbols` can be used for the structure type.

<a id="diobjcproperty"></a>

##### DIObjCProperty

`DIObjCProperty` nodes represent Objective-C property nodes.

    !3 = !DIObjCProperty(name: "foo", file: !1, line: 7, setter: "setFoo",
                         getter: "getFoo", attributes: 7, type: !2)

<a id="diimportedentity"></a>

##### DIImportedEntity

`DIImportedEntity` nodes represent entities (such as modules) imported into a compile unit. The `elements` field is a list of renamed entities (such as variables and subprograms) in the imported entity (such as module).

    !2 = !DIImportedEntity(tag: DW_TAG_imported_module, name: "foo", scope: !0,
                           entity: !1, line: 7, elements: !3)
    !3 = !{!4}
    !4 = !DIImportedEntity(tag: DW_TAG_imported_declaration, name: "bar", scope: !0,
                           entity: !5, line: 7)

<a id="dimacro"></a>

##### DIMacro

`DIMacro` nodes represent definition or undefinition of a macro identifiers. The `name:` field is the macro identifier, followed by macro parameters when defining a function-like macro, and the `value` field is the token-string used to expand the macro identifier.

    !2 = !DIMacro(macinfo: DW_MACINFO_define, line: 7, name: "foo(x)",
                  value: "((x) + 1)")
    !3 = !DIMacro(macinfo: DW_MACINFO_undef, line: 30, name: "foo")

<a id="dimacrofile"></a>

##### DIMacroFile

`DIMacroFile` nodes represent inclusion of source files. The `nodes:` field is a list of `DIMacro` and `DIMacroFile` nodes that appear in the included source file.

    !2 = !DIMacroFile(macinfo: DW_MACINFO_start_file, line: 7, file: !2,
                      nodes: !3)

<a id="dilabel"></a>

<a id="id25"></a>

##### DILabel

`DILabel` nodes represent labels within a [DISubprogram](#disubprogram). The `scope:` field must be one of either a [DILexicalBlockFile](#dilexicalblockfile), a [DILexicalBlock](#dilexicalblock), or a [DISubprogram](#disubprogram). The `name:` field is the label identifier. The `file:` field is the [DIFile](#difile) the label is present in. The `line:` and `column:` field are the source line and column within the file where the label is declared.

Furthermore, a label can be marked as artificial, i.e., compiler-generated, using `isArtificial:`. Such artificial labels are generated, e.g., by the `CoroSplit` pass. In addition, the `CoroSplit` pass also uses the `coroSuspendIdx:` field to identify the coroutine suspend points.

`scope:`, `name:`, `file:` and `line:` are mandatory. The remaining fields are optional.

    !2 = !DILabel(scope: !0, name: "foo", file: !1, line: 7, column: 4)
    !3 = !DILabel(scope: !0, name: "__coro_resume_3", file: !1, line: 9, column: 3, isArtificial: true, coroSuspendIdx: 3)

<a id="dicommonblock"></a>

##### DICommonBlock

`DICommonBlock` nodes represent Fortran common blocks. The `scope:` field is mandatory and points to a [DILexicalBlockFile](#dilexicalblockfile), a [DILexicalBlock](#dilexicalblock), or a [DISubprogram](#disubprogram). The `declaration:`, `name:`, `file:`, and `line:` fields are optional.

<a id="dimodule"></a>

##### DIModule

`DIModule` nodes represent a source language module, for example, a Clang module, or a Fortran module. The `scope:` field is mandatory and points to a [DILexicalBlockFile](#dilexicalblockfile), a [DILexicalBlock](#dilexicalblock), or a [DISubprogram](#disubprogram). The `name:` field is mandatory. The `configMacros:`, `includePath:`, `apinotes:`, `file:`, `line:`, and `isDecl:` fields are optional.

<a id="distringtype"></a>

##### DIStringType

`DIStringType` nodes represent a Fortran `CHARACTER(n)` type, with a dynamic length and location encoded as an expression. The `tag:` field is optional and defaults to `DW_TAG_string_type`. The `name:`, `stringLength:`, `stringLengthExpression`, `stringLocationExpression:`, `size:`, `align:`, and `encoding:` fields are optional.

If not present, the `size:` and `align:` fields default to the value zero.

The length in bits of the string is specified by the first of the following fields present:

- `stringLength:`, which points to a `DIVariable` whose value is the string length in bits.

- `stringLengthExpression:`, which points to a `DIExpression` which computes the length in bits.

- `size`, which contains the literal length in bits.

The `stringLocationExpression:` points to a `DIExpression` which describes the “data location” of the string object, if present.

<a id="tbaa-metadata"></a>

#### ‘`tbaa`’ Metadata

In LLVM IR, memory does not have types, so LLVM’s own type system is not suitable for doing type based alias analysis (TBAA). Instead, metadata is added to the IR to describe a type system of a higher level language. This can be used to implement C/C++ strict type aliasing rules, but it can also be used to implement custom alias analysis behavior for other languages.

This description of LLVM’s TBAA system is broken into two parts: [Semantics](#tbaa-node-semantics) talks about high level issues, and [Representation](#tbaa-node-representation) talks about the metadata encoding of various entities.

It is always possible to trace any TBAA node to a “root” TBAA node (details in the [Representation](#tbaa-node-representation) section). TBAA nodes with different roots have an unknown aliasing relationship, and LLVM conservatively infers `MayAlias` between them. The rules mentioned in this section only pertain to TBAA nodes living under the same root.

<a id="semantics"></a>

<a id="tbaa-node-semantics"></a>

##### Semantics

The TBAA metadata system, referred to as “struct path TBAA” (not to be confused with `tbaa.struct`), consists of the following high level concepts: *Type Descriptors*, further subdivided into scalar type descriptors and struct type descriptors; and *Access Tags*.

**Type descriptors** describe the type system of the higher level language being compiled. **Scalar type descriptors** describe types that do not contain other types. Each scalar type has a parent type, which must also be a scalar type or the TBAA root. Via this parent relation, scalar types within a TBAA root form a tree. **Struct type descriptors** denote types that contain a sequence of other type descriptors, at known offsets. These contained type descriptors can either be struct type descriptors themselves or scalar type descriptors.

**Access tags** are metadata nodes attached to load and store instructions. Access tags use type descriptors to describe the *location* being accessed in terms of the type system of the higher level language. Access tags are tuples consisting of a base type, an access type and an offset. The base type is a scalar type descriptor or a struct type descriptor, the access type is a scalar type descriptor, and the offset is a constant integer.

The access tag `(BaseTy, AccessTy, Offset)` can describe one of two things:

- If `BaseTy` is a struct type, the tag describes a memory access (load or store) of a value of type `AccessTy` contained in the struct type `BaseTy` at offset `Offset`.

- If `BaseTy` is a scalar type, `Offset` must be 0 and `BaseTy` and `AccessTy` must be the same; and the access tag describes a scalar access with scalar type `AccessTy`.

We first define an `ImmediateParent` relation on `(BaseTy, Offset)` tuples this way:

- If `BaseTy` is a scalar type then `ImmediateParent(BaseTy, 0)` is `(ParentTy, 0)` where `ParentTy` is the parent of the scalar type as described in the TBAA metadata. `ImmediateParent(BaseTy, Offset)` is undefined if `Offset` is non-zero.

- If `BaseTy` is a struct type then `ImmediateParent(BaseTy, Offset)` is `(NewTy, NewOffset)` where `NewTy` is the type contained in `BaseTy` at offset `Offset` and `NewOffset` is `Offset` adjusted to be relative within that inner type.

A memory access with an access tag `(BaseTy1, AccessTy1, Offset1)` aliases a memory access with an access tag `(BaseTy2, AccessTy2, Offset2)` if either `(BaseTy1, Offset1)` is reachable from `(Base2, Offset2)` via the `Parent` relation or vice versa. If memory accesses alias even though they are noalias according to `!tbaa` metadata, the behavior is undefined.

As a concrete example, the type descriptor graph for the following program

    struct Inner {
      int i;    // offset 0
      float f;  // offset 4
    };

    struct Outer {
      float f;  // offset 0
      double d; // offset 4
      struct Inner inner_a;  // offset 12
    };

    void f(struct Outer* outer, struct Inner* inner, float* f, int* i, char* c) {
      outer->f = 0;            // tag0: (OuterStructTy, FloatScalarTy, 0)
      outer->inner_a.i = 0;    // tag1: (OuterStructTy, IntScalarTy, 12)
      outer->inner_a.f = 0.0;  // tag2: (OuterStructTy, FloatScalarTy, 16)
      *f = 0.0;                // tag3: (FloatScalarTy, FloatScalarTy, 0)
    }

is (note that in C and C++, `char` can be used to access any arbitrary type):

    Root = "TBAA Root"
    CharScalarTy = ("char", Root, 0)
    FloatScalarTy = ("float", CharScalarTy, 0)
    DoubleScalarTy = ("double", CharScalarTy, 0)
    IntScalarTy = ("int", CharScalarTy, 0)
    InnerStructTy = {"Inner" (IntScalarTy, 0), (FloatScalarTy, 4)}
    OuterStructTy = {"Outer", (FloatScalarTy, 0), (DoubleScalarTy, 4),
                     (InnerStructTy, 12)}

with (e.g.) `ImmediateParent(OuterStructTy, 12)` = `(InnerStructTy, 0)`, `ImmediateParent(InnerStructTy, 0)` = `(IntScalarTy, 0)`, and `ImmediateParent(IntScalarTy, 0)` = `(CharScalarTy, 0)`.

<a id="representation"></a>

<a id="tbaa-node-representation"></a>

##### Representation

The root node of a TBAA type hierarchy is an `MDNode` with 0 operands or with exactly one `MDString` operand.

Scalar type descriptors are represented as an `MDNode` s with two operands. The first operand is an `MDString` denoting the name of the struct type. LLVM does not assign meaning to the value of this operand, it only cares about it being an `MDString`. The second operand is an `MDNode` which points to the parent for said scalar type descriptor, which is either another scalar type descriptor or the TBAA root. Scalar type descriptors can have an optional third argument, but that must be the constant integer zero.

Struct type descriptors are represented as `MDNode` s with an odd number of operands greater than 1. The first operand is an `MDString` denoting the name of the struct type. Like in scalar type descriptors the actual value of this name operand is irrelevant to LLVM. After the name operand, the struct type descriptors have a sequence of alternating `MDNode` and `ConstantInt` operands. With N starting from 1, the 2N - 1 th operand, an `MDNode`, denotes a contained field, and the 2N th operand, a `ConstantInt`, is the offset of the said contained field. The offsets must be in non-decreasing order.

Access tags are represented as `MDNode` s with either 3 or 4 operands. The first operand is an `MDNode` pointing to the node representing the base type. The second operand is an `MDNode` pointing to the node representing the access type. The third operand is a `ConstantInt` that states the offset of the access. If a fourth field is present, it must be a `ConstantInt` valued at 0 or 1. If it is 1 then the access tag states that the location being accessed is “constant” (meaning `pointsToConstantMemory` should return true; see [other useful AliasAnalysis methods](AliasAnalysis.html#other-useful-aliasanalysis-methods)). The TBAA root of the access type and the base type of an access tag must be the same, and that is the TBAA root of the access tag.

<a id="tbaa-struct-metadata"></a>

#### ‘`tbaa.struct`’ Metadata

The [llvm.memcpy](intrinsics-libc-and-arithmetic.md#int-memcpy) is often used to implement aggregate assignment operations in C and similar languages, however it is defined to copy a contiguous region of memory, which is more than strictly necessary for aggregate types which contain holes due to padding. Also, it doesn’t contain any TBAA information about the fields of the aggregate.

`!tbaa.struct` metadata can describe which memory subregions in a memcpy are padding and what the TBAA tags of the struct are.

The current metadata format is very simple. `!tbaa.struct` metadata nodes are a list of operands which are in conceptual groups of three. For each group of three, the first operand gives the byte offset of a field in bytes, the second gives its size in bytes, and the third gives its tbaa tag. e.g.:

    !4 = !{ i64 0, i64 4, !1, i64 8, i64 4, !2 }

This describes a struct with two fields. The first is at offset 0 bytes with size 4 bytes, and has tbaa tag !1. The second is at offset 8 bytes and has size 4 bytes and has tbaa tag !2.

Note that the fields need not be contiguous. In this example, there is a 4 byte gap between the two fields. This gap represents padding which does not carry useful data and need not be preserved.

<a id="noalias-and-alias-scope-metadata"></a>

#### ‘`noalias`’ and ‘`alias.scope`’ Metadata

`noalias` and `alias.scope` metadata provide the ability to specify generic noalias memory-access sets. This means that some collection of memory access instructions (loads, stores, memory-accessing calls, etc.) that carry `noalias` metadata can specifically be specified not to alias with some other collection of memory access instructions that carry `alias.scope` metadata. These metadata kinds may also be attached to `fence` instructions to indicate which scoped memory regions the fence does (or does not) concern; this allows alias analysis to prove that a fence cannot affect a particular memory location. If accesses from different collections alias, the behavior is undefined. Each type of metadata specifies a list of scopes where each scope has an id and a domain.

When evaluating an aliasing query, if for some domain, the set of scopes with that domain in one instruction’s `alias.scope` list is a subset of (or equal to) the set of scopes for that domain in another instruction’s `noalias` list, then the two memory accesses are assumed not to alias.

Because scopes in one domain don’t affect scopes in other domains, separate domains can be used to compose multiple independent noalias sets. This is used for example during inlining. As the noalias function parameters are turned into noalias scope metadata, a new domain is used every time the function is inlined.

The metadata identifying each domain is itself a list containing one or two entries. The first entry is the name of the domain. Note that if the name is a string then it can be combined across functions and translation units. A self-reference can be used to create globally unique domain names. A descriptive string may optionally be provided as a second list entry.

The metadata identifying each scope is also itself a list containing two or three entries. The first entry is the name of the scope. Note that if the name is a string then it can be combined across functions and translation units. A self-reference can be used to create globally unique scope names. A metadata reference to the scope’s domain is the second entry. A descriptive string may optionally be provided as a third list entry.

For example,

    ; Two scope domains:
    !0 = !{!0}
    !1 = !{!1}

    ; Some scopes in these domains:
    !2 = !{!2, !0}
    !3 = !{!3, !0}
    !4 = !{!4, !1}

    ; Some scope lists:
    !5 = !{!4} ; A list containing only scope !4
    !6 = !{!4, !3, !2}
    !7 = !{!3}

    ; These two instructions don't alias:
    %0 = load float, ptr %c, align 4, !alias.scope !5
    store float %0, ptr %arrayidx.i, align 4, !noalias !5

    ; These two instructions also don't alias (for domain !1, the set of scopes
    ; in the !alias.scope equals that in the !noalias list):
    %2 = load float, ptr %c, align 4, !alias.scope !5
    store float %2, ptr %arrayidx.i2, align 4, !noalias !6

    ; These two instructions may alias (for domain !0, the set of scopes in
    ; the !noalias list is not a superset of, or equal to, the scopes in the
    ; !alias.scope list):
    %2 = load float, ptr %c, align 4, !alias.scope !6
    store float %0, ptr %arrayidx.i, align 4, !noalias !7

<a id="fpmath-metadata"></a>

<a id="id26"></a>

#### ‘`fpmath`’ Metadata

`fpmath` metadata may be attached to any instruction of floating-point type. It can be used to express the maximum acceptable error in the result of that instruction, in ULPs, thus potentially allowing the compiler to use a more efficient but less accurate method of computing it. ULP is defined as follows:

> >
> If `x` is a real number that lies between two finite consecutive floating-point numbers `a` and `b`, without being equal to one of them, then `ulp(x) = |b - a|`, otherwise `ulp(x)` is the distance between the two non-equal finite floating-point numbers nearest `x`. Moreover, `ulp(NaN)` is `NaN`.
>
> 
The metadata node shall consist of a single positive float type number representing the maximum relative error, for example:

    !0 = !{ float 2.5 } ; maximum acceptable inaccuracy is 2.5 ULPs

<a id="range-metadata"></a>

<a id="id27"></a>

#### ‘`range`’ Metadata

`range` metadata may be attached only to `load`, `call` and `invoke` of integer or vector of integer types. It expresses the possible ranges the loaded value or the value returned by the called function at this call site is in. If the loaded or returned value is not in the specified range, a poison value is returned instead. The ranges are represented with a flattened list of integers. The loaded value or the value returned is known to be in the union of the ranges defined by each consecutive pair. Each pair has the following properties:

- The type must match the scalar type of the instruction.

- The pair `a,b` represents the range `[a,b)`.

- Both `a` and `b` are constants.

- The range is allowed to wrap.

- The range should not represent the full or empty set. That is, `a!=b`.

In addition, the pairs must be in signed order of the lower bound and they must be non-contiguous.

For vector-typed instructions, the range is applied element-wise.

Examples:

      %a = load i8, ptr %x, align 1, !range !0 ; Can only be 0 or 1
      %b = load i8, ptr %y, align 1, !range !1 ; Can only be 255 (-1), 0 or 1
      %c = call i8 @foo(),       !range !2 ; Can only be 0, 1, 3, 4 or 5
      %d = invoke i8 @bar() to label %cont
             unwind label %lpad, !range !3 ; Can only be -2, -1, 3, 4 or 5
      %e = load <2 x i8>, ptr %x, !range 0 ; Can only be <0 or 1, 0 or 1>
    ...
    !0 = !{ i8 0, i8 2 }
    !1 = !{ i8 255, i8 2 }
    !2 = !{ i8 0, i8 2, i8 3, i8 6 }
    !3 = !{ i8 -2, i8 0, i8 3, i8 6 }

<a id="nofpclass-metadata"></a>

<a id="id28"></a>

#### ‘`nofpclass`’ Metadata

`nofpclass` metadata may be attached only to `load` instructions. It asserts floating-point value classes which will not be loaded. The representation is an i32 constant integer encoding a 10-bit bitmask, with the same meaning and format as the [nofpclass](high-level-structure.md#nofpclass) attribute. If the loaded value is one of the specified floating-point classes, a poison value is returned. The interpretation does not depend on the floating-point environment. A zero value would be meaningless and is invalid.

Examples:

    %not.nan = load float, ptr %p, align 4, !nofpclass !0
    %not.inf = load <2 x float>, ptr %p, align 4, !nofpclass !1
    %only.normal = load double, ptr %p, align 8, !nofpclass !2
    %always.poison = load double, ptr %p, align 8, !nofpclass !3
    %not.nan.array = load [2 x <2 x float>], ptr %p, !nofpclass !1
    %not.nan.struct = load { 2 x float }, ptr %p, align 8, !nofpclass !1
    ...
    !0 = !{ i32 3 }
    !1 = !{ i32 516 }
    !2 = !{ i32 759 }
    !3 = !{ i32 1023 }

<a id="absolute-symbol-metadata"></a>

#### ‘`absolute_symbol`’ Metadata

`absolute_symbol` metadata may be attached to a global variable declaration. It marks the declaration as a reference to an absolute symbol, which causes the backend to use absolute relocations for the symbol even in position independent code, and expresses the possible ranges that the global variable’s *address* (not its value) is in, in the same format as `range` metadata, with the extension that the pair `all-ones,all-ones` may be used to represent the full set.

Example (assuming 64-bit pointers):

      @a = external global i8, !absolute_symbol !0 ; Absolute symbol in range [0,256)
      @b = external global i8, !absolute_symbol !1 ; Absolute symbol in range [0,2^64)

    ...
    !0 = !{ i64 0, i64 256 }
    !1 = !{ i64 -1, i64 -1 }

<a id="callees-metadata"></a>

#### ‘`callees`’ Metadata

`callees` metadata may be attached to indirect call sites. If `callees` metadata is attached to a call site, and any callee is not among the set of functions provided by the metadata, the behavior is undefined. The intent of this metadata is to facilitate optimizations such as indirect-call promotion. For example, in the code below, the call instruction may only target the `add` or `sub` functions:

    %result = call i64 %binop(i64 %x, i64 %y), !callees !0

    ...
    !0 = !{ptr @add, ptr @sub}

<a id="callback-metadata"></a>

#### ‘`callback`’ Metadata

`callback` metadata may be attached to a function declaration, or definition. (Call sites are excluded only due to the lack of a use case.) For ease of exposition, we’ll refer to the function annotated with metadata as a broker function. The metadata describes how the arguments of a call to the broker are in turn passed to the callback function specified by the metadata. Thus, the `callback` metadata provides a partial description of a call site inside the broker function with regards to the arguments of a call to the broker. The only semantic restriction on the broker function itself is that it is not allowed to inspect or modify arguments referenced in the `callback` metadata as pass-through to the callback function.

The broker is not required to actually invoke the callback function at runtime. However, the assumptions about not inspecting or modifying arguments that would be passed to the specified callback function still hold, even if the callback function is not dynamically invoked. The broker is allowed to invoke the callback function more than once per invocation of the broker. The broker is also allowed to invoke (directly or indirectly) the function passed as a callback through another use. Finally, the broker is also allowed to relay the callback callee invocation to a different thread.

The metadata is structured as follows: At the outer level, `callback` metadata is a list of `callback` encodings. Each encoding starts with a constant `i64` which describes the argument position of the callback function in the call to the broker. The following elements, except the last, describe what arguments are passed to the callback function. Each element is again an `i64` constant identifying the argument of the broker that is passed through, or `i64 -1` to indicate an unknown or inspected argument. The order in which they are listed has to be the same in which they are passed to the callback callee. The last element of the encoding is a boolean which specifies how variadic arguments of the broker are handled. If it is true, all variadic arguments of the broker are passed through to the callback function *after* the arguments encoded explicitly before.

In the code below, the `pthread_create` function is marked as a broker through the `!callback !1` metadata. In the example, there is only one callback encoding, namely `!2`, associated with the broker. This encoding identifies the callback function as the second argument of the broker (`i64 2`) and the sole argument of the callback function as the third one of the broker function (`i64 3`).

    declare !callback !1 dso_local i32 @pthread_create(ptr, ptr, ptr, ptr)

    ...
    !2 = !{i64 2, i64 3, i1 false}
    !1 = !{!2}

Another example is shown below. The callback callee is the second argument of the `__kmpc_fork_call` function (`i64 2`). The callee is given two unknown values (each identified by a `i64 -1`) and afterwards all variadic arguments that are passed to the `__kmpc_fork_call` call (due to the final `i1 true`).

    declare !callback !0 dso_local void @__kmpc_fork_call(ptr, i32, ptr, ...)

    ...
    !1 = !{i64 2, i64 -1, i64 -1, i1 true}
    !0 = !{!1}

<a id="exclude-metadata"></a>

#### ‘`exclude`’ Metadata

`exclude` metadata may be attached to a global variable to signify that its section should not be included in the final executable or shared library. This option is only valid for global variables with an explicit section targeting ELF or COFF. This is done using the `SHF_EXCLUDE` flag on ELF targets and the `IMAGE_SCN_LNK_REMOVE` and `IMAGE_SCN_MEM_DISCARDABLE` flags for COFF targets. Additionally, this metadata is only used as a flag, so the associated node must be empty. The explicit section should not conflict with any other sections that the user does not want removed after linking.

    @object = private constant [1 x i8] c"\00", section ".foo" !exclude !0

    ...
    !0 = !{}

<a id="unpredictable-metadata"></a>

#### ‘`unpredictable`’ Metadata

`unpredictable` metadata may be attached to any branch, select, or switch instruction. It can be used to express the unpredictability of control flow. Similar to the `llvm.expect` intrinsic, it may be used to alter optimizations related to compare and branch instructions. The metadata is treated as a boolean value; if it exists, it signals that the branch, select, or switch that it is attached to is completely unpredictable.

<a id="dereferenceable-metadata"></a>

<a id="md-dereferenceable"></a>

#### ‘`dereferenceable`’ Metadata

The existence of the `!dereferenceable` metadata on the instruction tells the optimizer that the value loaded is known to be dereferenceable at the current program point, otherwise the behavior is undefined. The number of bytes known to be dereferenceable is specified by the integer value in the metadata node. This is analogous to the ‘’dereferenceable’’ attribute on parameters and return values.

The `!deferenceable` metadata can be combined with the `!nofree` metadata to indicate that the pointer will stay dereferenceable forever.

<a id="dereferenceable-or-null-metadata"></a>

<a id="md-dereferenceable-or-null"></a>

#### ‘`dereferenceable_or_null`’ Metadata

The existence of the `!dereferenceable_or_null` metadata on the instruction tells the optimizer that the value loaded is known to be either dereferenceable at the current program point or null, otherwise the behavior is undefined. The number of bytes known to be dereferenceable is specified by the integer value in the metadata node. This is analogous to the ‘’dereferenceable_or_null’’ attribute on parameters and return values.

<a id="captures-metadata"></a>

#### ‘`captures`’ Metadata

The `!captures` metadata can only be applied to `store` instructions with a pointer-typed value operand. It restricts the capturing behavior of the store value operand in the same way the `captures(...)` attribute would do on a call. See the [pointer capture section](high-level-structure.md#pointercapture) for a detailed discussion of capture semantics.

The `!captures` metadata accepts a non-empty list of strings from the same set as the [captures attribute](high-level-structure.md#captures-attr): `!"address"`, `!"address_is_null"`, `!"provenance"` and `!"read_provenance"`. `!"none"` is not supported.

For example `store ptr %x, ptr %y, !captures !{!"address"}` indicates that the copy of pointer `%x` stored to location `%y` will only be used to inspect its integral address value, and not dereferenced. Dereferencing the pointer would result in undefined behavior.

Similarly `store ptr %x, ptr %y, !captures !{!"address", !"read_provenance"}` indicates that while reads through the stored pointer are allowed, writes would result in undefined behavior.

The `!captures` attribute makes no statement about other uses of `%x`, or uses of the stored-to memory location after it has been overwritten with a different value.

<a id="mem-cache-hint-metadata"></a>

#### ‘`mem.cache_hint`’ Metadata

The `!mem.cache_hint` metadata may be attached to any instruction that reads or writes memory, except non-intrinsic calls. Cache hints are not permitted on function calls because their memory behavior depends on attributes, which may change independently.

The `!mem.cache_hint` metadata provides target-specific cache control hints for the memory operation. This metadata is purely a performance hint: dropping or ignoring it must not change the observable behavior of the program (particularly, cache hints do not affect memory model semantics).

The `!mem.cache_hint` node must contain an even number of entries, alternating between `i32` operand numbers and metadata hint nodes.

Each operand number identifies the pointer operand to which the following hint node applies. For non-call instructions, the operand number is the IR operand index. For intrinsic calls, the operand number is the call argument index. Operand numbers must be unique and appear in increasing order within a `!mem.cache_hint` node and must refer to a pointer-typed operand.

For example, for a `load`, the pointer is operand 0. For a `store`, the value is operand 0 and the pointer is operand 1. For intrinsic calls such as `llvm.memcpy`, operand numbers correspond to argument positions: e.g., destination is argument 0 and source is argument 1.

Each hint node is a metadata node containing target-prefixed key/value pairs. Keys must be strings, and values must be either strings or integer constants. Keys within a single hint node must be unique.

The hint node keys are prefixed with a target identifier (e.g., `nvvm.`) and their interpretation is target-dependent. Each hint must describe a property of the individual memory access through the corresponding pointer operand. The IR verifier enforces only the structural rules above; validation of target-specific keys and values is performed by the corresponding backend. Unsupported properties may be silently ignored during code generation.

The following examples use `nvvm.` prefixed keys for NVIDIA GPU targets. Other targets may define their own prefixed keys.

Example: load with cache hints:

    %v = load i32, ptr addrspace(1) %p, align 4, !mem.cache_hint !0

    !0 = !{ i32 0, !1 }
    !1 = !{ !"nvvm.l1_eviction", !"first",
            !"nvvm.l2_eviction", !"first",
            !"nvvm.l2_prefetch_size", !"128B" }

Example: store with cache hints:

    store i32 %v, ptr addrspace(1) %p, align 4, !mem.cache_hint !0

    !0 = !{ i32 1, !1 }
    !1 = !{ !"nvvm.l1_eviction", !"last",
            !"nvvm.l2_eviction", !"last" }

Example: memcpy with per-operand hints:

    call void @llvm.memcpy.p1.p1.i64(ptr addrspace(1) %d,
                                      ptr addrspace(1) %s, i64 16, i1 false),
                                      !mem.cache_hint !0

    !0 = !{ i32 0, !1, i32 1, !2 }
    !1 = !{ !"nvvm.l1_eviction", !"last" }
    !2 = !{ !"nvvm.l1_eviction", !"first",
            !"nvvm.l2_prefetch_size", !"128B" }

<a id="llvm-loop"></a>

<a id="id29"></a>

#### ‘`llvm.loop`’

It is sometimes useful to attach information to loop constructs. Currently, loop metadata is implemented as metadata attached to the branch instruction in the loop latch block. The loop metadata node is a list of other metadata nodes, each representing a property of the loop. Usually, the first item of the property node is a string. For example, the `llvm.loop.unroll.count` suggests an unroll factor to the loop unroller:

      br i1 %exitcond, label %._crit_edge, label %.lr.ph, !llvm.loop !0
    ...
    !0 = !{!0, !1, !2}
    !1 = !{!"llvm.loop.unroll.enable"}
    !2 = !{!"llvm.loop.unroll.count", i32 4}

For legacy reasons, the first item of a loop metadata node must be a reference to itself. Before the advent of the ‘distinct’ keyword, this forced the preservation of otherwise identical metadata nodes. Since the loop-metadata node can be attached to multiple nodes, the ‘distinct’ keyword has become unnecessary.

Prior to the property nodes, one or two `DILocation` (debug location) nodes can be present in the list. The first, if present, identifies the source-code location where the loop begins. The second, if present, identifies the source-code location where the loop ends.

Loop metadata nodes cannot be used as unique identifiers. They are neither persistent for the same loop through transformations nor necessarily unique to just one loop.

<a id="llvm-loop-disable-nonforced"></a>

#### ‘`llvm.loop.disable_nonforced`’

This metadata disables all optional loop transformations unless explicitly instructed using other transformation metadata such as `llvm.loop.unroll.enable`. That is, no heuristic will try to determine whether a transformation is profitable. The purpose is to avoid that the loop is transformed to a different loop before an explicitly requested (forced) transformation is applied. For instance, loop fusion can make other transformations impossible. Mandatory loop canonicalizations such as loop rotation are still applied.

It is recommended to use this metadata in addition to any `llvm.loop.*` transformation directive. Also, any loop should have at most one directive applied to it (and a sequence of transformations built using followup-attributes). Otherwise, which transformation will be applied depends on implementation details such as the pass pipeline order.

See [Code Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-vectorize-and-llvm-loop-interleave"></a>

#### ‘`llvm.loop.vectorize`’ and ‘`llvm.loop.interleave`’

Metadata prefixed with `llvm.loop.vectorize` or `llvm.loop.interleave` are used to control per-loop vectorization and interleaving parameters such as vectorization width and interleave count. These metadata should be used in conjunction with `llvm.loop` loop identification metadata. The `llvm.loop.vectorize` and `llvm.loop.interleave` metadata are only optimization hints and the optimizer will only interleave and vectorize loops if it believes it is safe to do so. The `llvm.loop.parallel_accesses` metadata which contains information about loop-carried memory dependencies can be helpful in determining the safety of these transformations.

<a id="llvm-loop-interleave-count-metadata"></a>

#### ‘`llvm.loop.interleave.count`’ Metadata

This metadata suggests an interleave count to the loop interleaver. The first operand is the string `llvm.loop.interleave.count` and the second operand is an integer specifying the interleave count. For example:

    !0 = !{!"llvm.loop.interleave.count", i32 4}

Note that setting `llvm.loop.interleave.count` to 1 disables interleaving multiple iterations of the loop. If `llvm.loop.interleave.count` is set to 0 then the interleave count will be determined automatically.

<a id="llvm-loop-vectorize-enable-metadata"></a>

#### ‘`llvm.loop.vectorize.enable`’ Metadata

This metadata selectively enables or disables vectorization for the loop. The first operand is the string `llvm.loop.vectorize.enable` and the second operand is a bit. If the bit operand value is 1 vectorization is enabled. A value of 0 disables vectorization:

    !0 = !{!"llvm.loop.vectorize.enable", i1 0}
    !1 = !{!"llvm.loop.vectorize.enable", i1 1}

<a id="llvm-loop-vectorize-predicate-enable-metadata"></a>

#### ‘`llvm.loop.vectorize.predicate.enable`’ Metadata

This metadata selectively enables or disables creating predicated instructions for the loop, which can enable folding of the scalar epilogue loop into the main loop. The first operand is the string `llvm.loop.vectorize.predicate.enable` and the second operand is a bit. If the bit operand value is 1 predication is enabled. A value of 0 disables predication:

    !0 = !{!"llvm.loop.vectorize.predicate.enable", i1 0}
    !1 = !{!"llvm.loop.vectorize.predicate.enable", i1 1}

Additionally, enabling predication implicitly enables vectorization.

<a id="llvm-loop-vectorize-scalable-enable-metadata"></a>

#### ‘`llvm.loop.vectorize.scalable.enable`’ Metadata

This metadata selectively enables or disables scalable vectorization for the loop, and only has any effect if vectorization for the loop is already enabled. The first operand is the string `llvm.loop.vectorize.scalable.enable` and the second operand is a bit. If the bit operand value is 1 scalable vectorization is enabled, whereas a value of 0 reverts to the default fixed width vectorization:

    !0 = !{!"llvm.loop.vectorize.scalable.enable", i1 0}
    !1 = !{!"llvm.loop.vectorize.scalable.enable", i1 1}

<a id="llvm-loop-vectorize-width-metadata"></a>

#### ‘`llvm.loop.vectorize.width`’ Metadata

This metadata sets the target width of the vectorizer. The first operand is the string `llvm.loop.vectorize.width` and the second operand is an integer specifying the width. For example:

    !0 = !{!"llvm.loop.vectorize.width", i32 4}

Note that setting `llvm.loop.vectorize.width` to 1 disables vectorization of the loop. If `llvm.loop.vectorize.width` is set to 0 or if the loop does not have this metadata the width will be determined automatically.

<a id="llvm-loop-vectorize-followup-vectorized-metadata"></a>

#### ‘`llvm.loop.vectorize.followup_vectorized`’ Metadata

This metadata defines which loop attributes the vectorized loop will have. See [Code Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-vectorize-followup-epilogue-metadata"></a>

#### ‘`llvm.loop.vectorize.followup_epilogue`’ Metadata

This metadata defines which loop attributes the epilogue will have. The epilogue is not vectorized and is executed when either the vectorized loop is not known to preserve semantics (because e.g., it processes two arrays that are found to alias by a runtime check) or for the last iterations that do not fill a complete set of vector lanes. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-vectorize-followup-all-metadata"></a>

#### ‘`llvm.loop.vectorize.followup_all`’ Metadata

Attributes in the metadata will be added to both the vectorized and epilogue loop. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-vectorize-body-metadata"></a>

#### ‘`llvm.loop.vectorize.body`’ Metadata

This metadata is automatically added by the loop vectorizer to the vectorized loop body. It is used by subsequent optimization passes (such as the loop unroller and `WarnMissedTransforms`) to emit more precise optimization remarks that identify the loop as a vector loop.

The first operand is the string `llvm.loop.vectorize.body` and the second operand is an integer. A value of 1 indicates this is a vectorized loop body:

    !0 = !{!"llvm.loop.vectorize.body", i32 1}

<a id="llvm-loop-vectorize-epilogue-metadata"></a>

#### ‘`llvm.loop.vectorize.epilogue`’ Metadata

This metadata is automatically added by the loop vectorizer to the scalar remainder (epilogue) loop to identify it as such. It is used by subsequent optimization passes (such as the loop unroller and `WarnMissedTransforms`) to emit more precise optimization remarks that distinguish between the vectorized loop and its scalar remainder.

Together these two attributes provide a four-way classification:

- `body` only: main vectorized loop body

- `epilogue` only: scalar epilogue loop after vectorization

- Both `body` and `epilogue`: vectorized epilogue (a remainder loop that was itself vectorized during epilogue vectorization)

- Neither: a plain loop not produced by the vectorizer

The first operand is the string `llvm.loop.vectorize.epilogue` and the second operand is an integer. A value of 1 indicates the loop is a remainder loop:

    !0 = !{!"llvm.loop.vectorize.epilogue", i32 1}

<a id="llvm-loop-unroll"></a>

#### ‘`llvm.loop.unroll`’

Metadata prefixed with `llvm.loop.unroll` are loop unrolling optimization hints such as the unroll factor. `llvm.loop.unroll` metadata should be used in conjunction with `llvm.loop` loop identification metadata. The `llvm.loop.unroll` metadata are only optimization hints and the unrolling will only be performed if the optimizer believes it is safe to do so.

<a id="llvm-loop-unroll-count-metadata"></a>

#### ‘`llvm.loop.unroll.count`’ Metadata

This metadata suggests an unroll factor to the loop unroller. The first operand is the string `llvm.loop.unroll.count` and the second operand is a positive integer specifying the unroll factor. For example:

    !0 = !{!"llvm.loop.unroll.count", i32 4}

If the trip count of the loop is less than the unroll count the loop will be partially unrolled.

<a id="llvm-loop-unroll-disable-metadata"></a>

#### ‘`llvm.loop.unroll.disable`’ Metadata

This metadata disables loop unrolling. The metadata has a single operand which is the string `llvm.loop.unroll.disable`. For example:

    !0 = !{!"llvm.loop.unroll.disable"}

<a id="llvm-loop-unroll-runtime-disable-metadata"></a>

#### ‘`llvm.loop.unroll.runtime.disable`’ Metadata

This metadata disables runtime loop unrolling. The metadata has a single operand which is the string `llvm.loop.unroll.runtime.disable`. For example:

    !0 = !{!"llvm.loop.unroll.runtime.disable"}

<a id="llvm-loop-unroll-enable-metadata"></a>

#### ‘`llvm.loop.unroll.enable`’ Metadata

This metadata suggests that the loop should be fully unrolled if the trip count is known at compile time and partially unrolled if the trip count is not known at compile time. The metadata has a single operand which is the string `llvm.loop.unroll.enable`. For example:

    !0 = !{!"llvm.loop.unroll.enable"}

<a id="llvm-loop-unroll-full-metadata"></a>

#### ‘`llvm.loop.unroll.full`’ Metadata

This metadata suggests that the loop should be unrolled fully. The metadata has a single operand which is the string `llvm.loop.unroll.full`. For example:

    !0 = !{!"llvm.loop.unroll.full"}

<a id="llvm-loop-unroll-followup-metadata"></a>

#### ‘`llvm.loop.unroll.followup`’ Metadata

This metadata defines which loop attributes the unrolled loop will have. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-unroll-followup-remainder-metadata"></a>

#### ‘`llvm.loop.unroll.followup_remainder`’ Metadata

This metadata defines which loop attributes the remainder loop after partial/runtime unrolling will have. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-unroll-and-jam"></a>

#### ‘`llvm.loop.unroll_and_jam`’

This metadata is treated very similarly to the `llvm.loop.unroll` metadata above, but affect the unroll and jam pass. In addition any loop with `llvm.loop.unroll` metadata but no `llvm.loop.unroll_and_jam` metadata will disable unroll and jam (so `llvm.loop.unroll` metadata will be left to the unroller, plus `llvm.loop.unroll.disable` metadata will disable unroll and jam too.)

The metadata for unroll and jam otherwise is the same as for `unroll`. `llvm.loop.unroll_and_jam.enable`, `llvm.loop.unroll_and_jam.disable` and `llvm.loop.unroll_and_jam.count` do the same as for unroll. `llvm.loop.unroll_and_jam.full` is not supported. Again these are only hints and the normal safety checks will still be performed.

<a id="llvm-loop-unroll-and-jam-count-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.count`’ Metadata

This metadata suggests an unroll and jam factor to use, similarly to `llvm.loop.unroll.count`. The first operand is the string `llvm.loop.unroll_and_jam.count` and the second operand is a positive integer specifying the unroll factor. For example:

    !0 = !{!"llvm.loop.unroll_and_jam.count", i32 4}

If the trip count of the loop is less than the unroll count the loop will be partially unroll and jammed.

<a id="llvm-loop-unroll-and-jam-disable-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.disable`’ Metadata

This metadata disables loop unroll and jamming. The metadata has a single operand which is the string `llvm.loop.unroll_and_jam.disable`. For example:

    !0 = !{!"llvm.loop.unroll_and_jam.disable"}

<a id="llvm-loop-unroll-and-jam-enable-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.enable`’ Metadata

This metadata suggests that the loop should be fully unroll and jammed if the trip count is known at compile time and partially unrolled if the trip count is not known at compile time. The metadata has a single operand which is the string `llvm.loop.unroll_and_jam.enable`. For example:

    !0 = !{!"llvm.loop.unroll_and_jam.enable"}

<a id="llvm-loop-unroll-and-jam-followup-outer-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.followup_outer`’ Metadata

This metadata defines which loop attributes the outer unrolled loop will have. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-unroll-and-jam-followup-inner-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.followup_inner`’ Metadata

This metadata defines which loop attributes the inner jammed loop will have. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-unroll-and-jam-followup-remainder-outer-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.followup_remainder_outer`’ Metadata

This metadata defines which attributes the epilogue of the outer loop will have. This loop is usually unrolled, meaning there is no such loop. This attribute will be ignored in this case. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-unroll-and-jam-followup-remainder-inner-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.followup_remainder_inner`’ Metadata

This metadata defines which attributes the inner loop of the epilogue will have. The outer epilogue will usually be unrolled, meaning there can be multiple inner remainder loops. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-unroll-and-jam-followup-all-metadata"></a>

#### ‘`llvm.loop.unroll_and_jam.followup_all`’ Metadata

Attributes specified in the metadata is added to all `llvm.loop.unroll_and_jam.*` loops. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-licm-versioning-disable-metadata"></a>

#### ‘`llvm.loop.licm_versioning.disable`’ Metadata

This metadata indicates that the loop should not be versioned for the purpose of enabling loop-invariant code motion (LICM). The metadata has a single operand which is the string `llvm.loop.licm_versioning.disable`. For example:

    !0 = !{!"llvm.loop.licm_versioning.disable"}

<a id="llvm-loop-distribute-enable-metadata"></a>

#### ‘`llvm.loop.distribute.enable`’ Metadata

Loop distribution allows splitting a loop into multiple loops. Currently, this is only performed if the entire loop cannot be vectorized due to unsafe memory dependencies. The transformation will attempt to isolate the unsafe dependencies into their own loop.

This metadata can be used to selectively enable or disable distribution of the loop. The first operand is the string `llvm.loop.distribute.enable` and the second operand is a bit. If the bit operand value is 1 distribution is enabled. A value of 0 disables distribution:

    !0 = !{!"llvm.loop.distribute.enable", i1 0}
    !1 = !{!"llvm.loop.distribute.enable", i1 1}

This metadata should be used in conjunction with `llvm.loop` loop identification metadata.

<a id="llvm-loop-distribute-followup-coincident-metadata"></a>

#### ‘`llvm.loop.distribute.followup_coincident`’ Metadata

This metadata defines which attributes extracted loops with no cyclic dependencies will have (i.e., can be vectorized). See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-distribute-followup-sequential-metadata"></a>

#### ‘`llvm.loop.distribute.followup_sequential`’ Metadata

This metadata defines which attributes the isolated loops with unsafe memory dependencies will have. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-distribute-followup-fallback-metadata"></a>

#### ‘`llvm.loop.distribute.followup_fallback`’ Metadata

If loop versioning is necessary, this metadata defined the attributes the non-distributed fallback version will have. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-distribute-followup-all-metadata"></a>

#### ‘`llvm.loop.distribute.followup_all`’ Metadata

The attributes in this metadata are added to all followup loops of the loop distribution pass. See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-isdistributed-metadata"></a>

#### ‘`llvm.loop.isdistributed`’ Metadata

If a loop was successfully processed by the loop distribution pass, this metadata is added (i.e., has been distributed). See [Transformation Metadata](TransformMetadata.html#transformation-metadata) for details.

<a id="llvm-loop-estimated-trip-count-metadata"></a>

#### ‘`llvm.loop.estimated_trip_count`’ Metadata

This metadata records an estimated trip count for the loop. The first operand is the string `llvm.loop.estimated_trip_count`. The second operand is an integer constant of type `i32` or smaller specifying the estimate. For example:

    !0 = !{!"llvm.loop.estimated_trip_count", i32 8}

<a id="purpose"></a>

##### Purpose

A loop’s estimated trip count is an estimate of the average number of loop iterations (specifically, the number of times the loop’s header executes) each time execution reaches the loop. It is usually only an estimate based on, for example, profile data. The actual number of iterations might vary widely.

The estimated trip count serves as a parameter for various loop transformations and typically helps estimate transformation cost. For example, it can help determine how many iterations to peel or how aggressively to unroll.

<a id="initialization-and-maintenance"></a>

##### Initialization and Maintenance

Passes should interact with estimated trip counts always via `llvm::getLoopEstimatedTripCount` and `llvm::setLoopEstimatedTripCount`.

When the `llvm.loop.estimated_trip_count` metadata is not present on a loop, `llvm::getLoopEstimatedTripCount` estimates the loop’s trip count from the loop’s `branch_weights` metadata under the assumption that the latter still accurately encodes the program’s original profile data. However, as passes transform existing loops and create new loops, they must be free to update and create `branch_weights` metadata in a way that maintains accurate block frequencies. Trip counts estimated from this new `branch_weights` metadata are not necessarily useful to the passes that consume estimated trip counts.

For this reason, when a pass transforms or creates loops, the pass should separately estimate new trip counts based on the estimated trip counts that `llvm::getLoopEstimatedTripCount` returns at the start of the pass, and the pass should record the new estimates by calling `llvm::setLoopEstimatedTripCount`, which creates or updates `llvm.loop.estimated_trip_count` metadata. Once this metadata is present on a loop, `llvm::getLoopEstimatedTripCount` returns its value instead of estimating the trip count from the loop’s `branch_weights` metadata.

<a id="zero"></a>

##### Zero

Some passes set `llvm.loop.estimated_trip_count` to 0. For example, after peeling 10 or more iterations from a loop with an estimated trip count of 10, `llvm.loop.estimated_trip_count` becomes 0 on the remaining loop. It indicates that, each time execution reaches the peeled iterations, execution is estimated to exit them without reaching the remaining loop’s header.

Even if the probability of reaching a loop’s header is low, if it is reached, it is the start of an iteration. Consequently, some passes historically assume that `llvm::getLoopEstimatedTripCount` always returns a positive count or `std::nullopt`. Thus, it returns `std::nullopt` when `llvm.loop.estimated_trip_count` is 0.

<a id="llvm-licm-disable-metadata"></a>

#### ‘`llvm.licm.disable`’ Metadata

This metadata indicates that loop-invariant code motion (LICM) should not be performed on this loop. The metadata has a single operand which is the string `llvm.licm.disable`. For example:

    !0 = !{!"llvm.licm.disable"}

Note that although it operates per loop it isn’t given the `llvm.loop` prefix as it is not affected by the `llvm.loop.disable_nonforced` metadata.

<a id="llvm-access-group-metadata"></a>

#### ‘`llvm.access.group`’ Metadata

`llvm.access.group` metadata can be attached to any instruction that potentially accesses memory. It can point to a single distinct metadata node, which we call access group. This node represents all memory access instructions referring to it via `llvm.access.group`. When an instruction belongs to multiple access groups, it can also point to a list of accesses groups, illustrated by the following example.

    %val = load i32, ptr %arrayidx, !llvm.access.group !0
    ...
    !0 = !{!1, !2}
    !1 = distinct !{}
    !2 = distinct !{}

It is illegal for the list node to be empty since it might be confused with an access group.

The access group metadata node must be ‘distinct’ to avoid collapsing multiple access groups by content. An access group metadata node must always be empty which can be used to distinguish an access group metadata node from a list of access groups. Being empty avoids the situation that the content must be updated which, because metadata is immutable by design, would required finding and updating all references to the access group node.

The access group can be used to refer to a memory access instruction without pointing to it directly (which is not possible in global metadata). Currently, the only metadata making use of it is `llvm.loop.parallel_accesses`.

<a id="llvm-loop-parallel-accesses-metadata"></a>

#### ‘`llvm.loop.parallel_accesses`’ Metadata

The `llvm.loop.parallel_accesses` metadata refers to one or more access group metadata nodes (see `llvm.access.group`). It denotes that no loop-carried memory dependence exist between it and other instructions in the loop with this metadata.

Let `m1` and `m2` be two instructions that both have the `llvm.access.group` metadata to the access group `g1`, respectively `g2` (which might be identical). If a loop contains both access groups in its `llvm.loop.parallel_accesses` metadata, then the compiler can assume that there is no dependency between `m1` and `m2` carried by this loop. Instructions that belong to multiple access groups are considered having this property if at least one of the access groups matches the `llvm.loop.parallel_accesses` list.

If all memory-accessing instructions in a loop have `llvm.access.group` metadata that each refer to one of the access groups of a loop’s `llvm.loop.parallel_accesses` metadata, then the loop has no loop carried memory dependencies and is considered to be a parallel loop. If there is a loop-carried dependency, the behavior is undefined.

Note that if not all memory access instructions belong to an access group referred to by `llvm.loop.parallel_accesses`, then the loop must not be considered trivially parallel. Additional memory dependence analysis is required to make that determination. As a fail-safe mechanism, this causes loops that were originally parallel to be considered sequential (if optimization passes that are unaware of the parallel semantics insert new memory instructions into the loop body).

Example of a loop that is considered parallel due to its correct use of both `llvm.access.group` and `llvm.loop.parallel_accesses` metadata types.

    for.body:
      ...
      %val0 = load i32, ptr %arrayidx, !llvm.access.group !1
      ...
      store i32 %val0, ptr %arrayidx1, !llvm.access.group !1
      ...
      br i1 %exitcond, label %for.end, label %for.body, !llvm.loop !0

    for.end:
    ...
    !0 = distinct !{!0, !{!"llvm.loop.parallel_accesses", !1}}
    !1 = distinct !{}

It is also possible to have nested parallel loops:

    outer.for.body:
      ...
      %val1 = load i32, ptr %arrayidx3, !llvm.access.group !4
      ...
      br label %inner.for.body

    inner.for.body:
      ...
      %val0 = load i32, ptr %arrayidx1, !llvm.access.group !3
      ...
      store i32 %val0, ptr %arrayidx2, !llvm.access.group !3
      ...
      br i1 %exitcond, label %inner.for.end, label %inner.for.body, !llvm.loop !1

    inner.for.end:
      ...
      store i32 %val1, ptr %arrayidx4, !llvm.access.group !4
      ...
      br i1 %exitcond, label %outer.for.end, label %outer.for.body, !llvm.loop !2

    outer.for.end:                                          ; preds = %for.body
    ...
    !1 = distinct !{!1, !{!"llvm.loop.parallel_accesses", !3}}     ; metadata for the inner loop
    !2 = distinct !{!2, !{!"llvm.loop.parallel_accesses", !3, !4}} ; metadata for the outer loop
    !3 = distinct !{} ; access group for instructions in the inner loop (which are implicitly contained in outer loop as well)
    !4 = distinct !{} ; access group for instructions in the outer, but not the inner loop

<a id="llvm-loop-mustprogress-metadata"></a>

<a id="langref-llvm-loop-mustprogress"></a>

#### ‘`llvm.loop.mustprogress`’ Metadata

The `llvm.loop.mustprogress` metadata indicates that this loop is required to terminate, unwind, or interact with the environment in an observable way e.g. via a volatile memory access, I/O, or other synchronization. If such a loop is not found to interact with the environment in an observable way, the loop may be removed. This corresponds to the `mustprogress` function attribute.

<a id="irr-loop-metadata"></a>

#### ‘`irr_loop`’ Metadata

`irr_loop` metadata may be attached to the terminator instruction of a basic block that’s an irreducible loop header (note that an irreducible loop has more than once header basic blocks.) If `irr_loop` metadata is attached to the terminator instruction of a basic block that is not really an irreducible loop header, the behavior is undefined. The intent of this metadata is to improve the accuracy of the block frequency propagation. For example, in the code below, the block `header0` may have a loop header weight (relative to the other headers of the irreducible loop) of 100:

    header0:
    ...
    br i1 %cmp, label %t1, label %t2, !irr_loop !0

    ...
    !0 = !{"loop_header_weight", i64 100}

Irreducible loop header weights are typically based on profile data.

<a id="invariant-load-metadata"></a>

<a id="md-invariant-load"></a>

#### ‘`invariant.load`’ Metadata

The `invariant.load` metadata may be attached to load operations or to intrinsic calls that only read memory (though it is possible this may be extended in the future if the need arises).

If an `invariant.load`-tagged operation is executed, every memory location read by that operation must contain the same value at all points in the program where that memory is dereferenceable; otherwise, the behavior is undefined.

An `invariant.load` tag may be placed on operations that read inaccessible memory or non-memory values (such as registers). These load-like operations must be invariant throughout the lifetime of the state being read.

    ;; Invariant load of a pointer.
    load i32, ptr %ptr, !invariant.load !0

    ;; Invariant masked vector load.
    call <4 x i32> @llvm.masked.load.v4i32.p0(ptr %p, <4 x i1> %mask, <4 x i32> zeroinitializer), !invariant.load !0

    ;; Invariant "load" from a register.
    call i32 @llvm.read_register.i32(metadata !1), !invariant.load !0
    !0 = !{}
    !1 = !{!"reg"}

<a id="invariant-group-metadata"></a>

<a id="md-invariant-group"></a>

#### ‘`invariant.group`’ Metadata

The experimental `invariant.group` metadata may be attached to `load`/`store` instructions referencing a single metadata with no entries. The existence of the `invariant.group` metadata on the instruction tells the optimizer that every `load` and `store` to the same pointer operand can be assumed to load or store the same value (but see the `llvm.launder.invariant.group` intrinsic which affects when two pointers are considered the same). Pointers returned by bitcast or getelementptr with only zero indices are considered the same.

Note that the metadata value in invariant.group carries no semantic value. Because it must have no entries, all invariant.group annotations in a module reference the same uniqued empty node.

Examples:

    @unknownPtr = external global i8
    ...
    %ptr = alloca i8
    store i8 42, ptr %ptr, !invariant.group !0
    call void @foo(ptr %ptr)

    %a = load i8, ptr %ptr, !invariant.group !0 ; Can assume that value under %ptr didn't change
    call void @foo(ptr %ptr)

    %newPtr = call ptr @getPointer(ptr %ptr)
    %c = load i8, ptr %newPtr, !invariant.group !0 ; Can't assume anything, because we only have information about %ptr

    %unknownValue = load i8, ptr @unknownPtr
    store i8 %unknownValue, ptr %ptr, !invariant.group !0 ; Can assume that %unknownValue == 42

    call void @foo(ptr %ptr)
    %newPtr2 = call ptr @llvm.launder.invariant.group.p0(ptr %ptr)
    %d = load i8, ptr %newPtr2, !invariant.group !0  ; Can't step through launder.invariant.group to get value of %ptr

    ...
    declare void @foo(ptr)
    declare ptr @getPointer(ptr)
    declare ptr @llvm.launder.invariant.group.p0(ptr)

    !0 = !{}

The `invariant.group` metadata must be dropped when replacing one pointer by another based on aliasing information. This is because `invariant.group` is tied to the SSA value of the pointer operand.

    %v = load i8, ptr %x, !invariant.group !0
    ; if %x mustalias %y then we can replace the above instruction with
    %v = load i8, ptr %y

Note that this is an experimental feature, which means that its semantics might change in the future.

<a id="type-metadata"></a>

#### ‘`type`’ Metadata

See [Type Metadata](TypeMetadata.html).

<a id="callee-type-metadata"></a>

<a id="metadata-callee-type"></a>

#### ‘`callee_type`’ Metadata

The `!callee_type` metadata is introduced to support the generation of a call graph section in the object file. The `!callee_type` metadata is used to identify the types of the intended callees of indirect call instructions. The `!callee_type` metadata is a list of one or more generalized `!callgraph` metadata objects (See the [‘callgraph’ Metadata](#metadata-callgraph) section) with each `!callgraph` metadata pointing to a callee’s [type identifier](#calleetype-type-identifier).

While `!callee_type` and `!callgraph` are private to the Call Graph Section pipeline and contain no offsets, LLVM’s [Control Flow Integrity (CFI)](https://clang.org/docs/ControlFlowIntegrity.html) uses a structurally similar `!type` metadata in its implementation (See [Type Metadata](TypeMetadata.html)), which shares the same type identifier format but includes a leading offset for vtable compatibility.

<a id="type-identifier"></a>

<a id="calleetype-type-identifier"></a>

##### Type identifier

The type for an indirect call target is the callee’s function signature. Mapping from a type to an identifier is an ABI detail. In the current implementation, an identifier of type T is computed as follows:

- Obtain the generalized mangled name for “typeinfo name for T”.

- Compute MD5 hash of the name as a string.

- Reinterpret the first 8 bytes of the hash as a little-endian 64-bit integer.

To avoid mismatched pointer types, generalizations are applied. Pointers in return and argument types are treated as equivalent as long as the qualifiers for the type they point to match. For example, `char*`, `char**`, and `int*` are considered equivalent types. However, `char*` and `const char*` are considered distinct types.

<a id="callgraph-metadata"></a>

<a id="metadata-callgraph"></a>

#### ‘`callgraph`’ Metadata

The `!callgraph` metadata associates a function definition with its type identifier. It uses the same generalized type encoding as the `!type` metadata used for CFI and WPD, and allows us to emit a call graph section in the object file that can be used to compute a conservative and precise static call graph in a linked binary.

<a id="id30"></a>

##### Syntax:

A `!callgraph` metadata node is attached to a function definition as follows:

    define void @foo() !callgraph !0
    !0 = !{!"_ZTSFvvE.generalized"}

The metadata node is a 1-element tuple containing only the generalized type identifier as `MDString`.

<a id="relation-to-control-flow-integrity-cfi"></a>

##### Relation to Control Flow Integrity (CFI)

While `!callgraph` metadata is structurally similar to LLVM’s `!type` metadata (which is used by [Control Flow Integrity (CFI)](https://clang.org/docs/ControlFlowIntegrity.html) and Whole Program Devirtualization), they serve different purposes:

- `!type` (CFI): Contains an offset (e.g., `!{i64 0, !"_ZTSFvvE.generalized"}`) to support virtual table offset calculations and devirtualization.

- `!callgraph` (Call Graph Section): Does not contain an offset. This is private to the Call Graph Section pipeline.

The generalized type identifier format used by both is identical. For more details on the generalized type identifier format and CFI’s metadata, see [Type Metadata](TypeMetadata.html) and [‘callee_type’ Metadata](#metadata-callee-type).

<a id="associated-metadata"></a>

#### ‘`associated`’ Metadata

The `associated` metadata may be attached to a global variable definition with a single argument that references a global object (optionally through an alias).

This metadata lowers to the ELF section flag `SHF_LINK_ORDER` which prevents discarding of the global variable in linker GC unless the referenced object is also discarded. The linker support for this feature is spotty. For best compatibility, globals carrying this metadata should:

- Be in `@llvm.compiler.used`.

- If the referenced global variable is in a comdat, be in the same comdat.

`!associated` can not express a many-to-one relationship. A global variable with the metadata should generally not be referenced by a function: the function may be inlined into other functions, leading to more references to the metadata. Ideally we would want to keep metadata alive as long as any inline location is alive, but this many-to-one relationship is not representable. Moreover, if the metadata is retained while the function is discarded, the linker will report an error of a relocation referencing a discarded section.

The metadata is often used with an explicit section consisting of valid C identifiers so that the runtime can find the metadata section with linker-defined encapsulation symbols `__start_<section_name>` and `__stop_<section_name>`.

It does not have any effect on non-ELF targets.

Example:

    $a = comdat any
    @a = global i32 1, comdat $a
    @b = internal global i32 2, comdat $a, section "abc", !associated !0
    !0 = !{ptr @a}

<a id="prof-metadata"></a>

#### ‘`prof`’ Metadata

The `prof` metadata is used to record profile data in the IR. The first operand of the metadata node indicates the profile metadata type. There are currently 3 types: [branch_weights](#prof-node-branch-weights), [function_entry_count](#prof-node-function-entry-count), and [VP](#prof-node-vp).

<a id="branch-weights"></a>

<a id="prof-node-branch-weights"></a>

##### branch_weights

Branch weight metadata attached to a branch, select, switch or call instruction represents the likeliness of the associated branch being taken. For more information, see [LLVM Branch Weight Metadata](BranchWeightMetadata.html).

<a id="function-entry-count"></a>

<a id="prof-node-function-entry-count"></a>

##### function_entry_count

Function entry count metadata can be attached to function definitions to record the number of times the function is called. Used with BFI information, it is also used to derive the basic block profile count. For more information, see [LLVM Branch Weight Metadata](BranchWeightMetadata.html).

<a id="vp"></a>

<a id="prof-node-vp"></a>

##### VP

VP (value profile) metadata can be attached to instructions that have value profile information. Currently this is indirect calls (where it records the hottest callees) and calls to memory intrinsics, such as memcpy, memmove, and memset (where it records the hottest byte lengths).

Each VP metadata node contains “VP” string, then a `uint32_t` value for the value profiling kind, a `uint64_t` value for the total number of times the instruction is executed, followed by `uint64_t` value and execution count pairs. The value profiling kind is 0 for indirect call targets and 1 for memory operations. For indirect call targets, each profile value is a hash of the callee function name, and for memory operations each value is the byte length. It is illegal to have duplicate profile values (e.g., duplicate function hashes for indirect calls or byte lengths for memory operations).

Note that the value counts do not need to add up to the total count listed in the third operand (in practice only the top hottest values are tracked and reported).

Indirect call example:

    call void %f(), !prof !1
    !1 = !{!"VP", i32 0, i64 1600, i64 7651369219802541373, i64 1030, i64 -4377547752858689819, i64 410}

Note that the VP type is 0 (the second operand), which indicates this is an indirect call value profile data. The third operand indicates that the indirect call executed 1600 times. The 4th and 6th operands give the hashes of the 2 hottest target functions’ names (this is the same hash used to represent function names in the profile database), and the 5th and 7th operands give the execution count that each of the respective prior target functions was called.

<a id="annotation-metadata"></a>

<a id="md-annotation"></a>

#### ‘`annotation`’ Metadata

The `annotation` metadata can be used to attach a tuple of annotation strings or a tuple of a tuple of annotation strings to any instruction. This metadata does not impact the semantics of the program and may only be used to provide additional insight about the program and transformations to users.

Example:

    %a.addr = alloca ptr, align 8, !annotation !0
    !0 = !{!"auto-init"}

Embedding tuple of strings example:

    %a.ptr = getelementptr ptr, ptr %base, i64 0. !annotation !0
    !0 = !{!1}
    !1 = !{!"gep offset", !"0"}

<a id="func-sanitize-metadata"></a>

#### ‘`func_sanitize`’ Metadata

The `func_sanitize` metadata is used to attach two values for the function sanitizer instrumentation. The first value is the ubsan function signature. The second value is the address of the proxy variable which stores the address of the RTTI descriptor. If [prologue](high-level-structure.md#prologuedata) and ‘`func_sanitize`’ are used at the same time, [prologue](high-level-structure.md#prologuedata) is emitted before ‘`func_sanitize`’ in the output.

Example:

    @__llvm_rtti_proxy = private unnamed_addr constant ptr @_ZTIFvvE
    define void @_Z3funv() !func_sanitize !0 {
      return void
    }
    !0 = !{i32 846595819, ptr @__llvm_rtti_proxy}

<a id="kcfi-type-metadata"></a>

<a id="md-kcfi-type"></a>

#### ‘`kcfi_type`’ Metadata

The `kcfi_type` metadata can be used to attach a type identifier to functions that can be called indirectly. The type data is emitted before the function entry in the assembly. Indirect calls with the [kcfi operand bundle](high-level-structure.md#ob-kcfi) will emit a check that compares the type identifier to the metadata.

Example:

    define dso_local i32 @f() !kcfi_type !0 {
      ret i32 0
    }
    !0 = !{i32 12345678}

Clang emits `kcfi_type` metadata nodes for address-taken functions with `-fsanitize=kcfi`.

<a id="pcsections-metadata"></a>

#### ‘`pcsections`’ Metadata

The `pcsections` metadata can be attached to instructions and functions, for which addresses, viz. program counters (PCs), are to be emitted in specially encoded binary sections. More details can be found in the [PC Sections Metadata](PCSectionsMetadata.html) documentation.

<a id="memprof-metadata"></a>

<a id="md-memprof"></a>

#### ‘`memprof`’ Metadata

The `memprof` metadata is used to record memory profile data on heap allocation calls. Multiple context-sensitive profiles can be represented with a single `memprof` metadata attachment.

Example:

    %call = call ptr @_Znam(i64 10), !memprof !0, !callsite !5
    !0 = !{!1, !3}
    !1 = !{!2, !"cold"}
    !2 = !{i64 4854880825882961848, i64 1905834578520680781}
    !3 = !{!4, !"notcold"}
    !4 = !{i64 4854880825882961848, i64 -6528110295079665978}
    !5 = !{i64 4854880825882961848}

Each operand in the `memprof` metadata attachment describes the profiled behavior of memory allocated by the associated allocation for a given context. In the above example, there were 2 profiled contexts, one allocating memory that was typically cold and one allocating memory that was typically not cold.

The format of the metadata describing a context specific profile (e.g. `!1` and `!3` above) requires a first operand that is a metadata node describing the context, followed by a list of string metadata tags describing the profile behavior (e.g., `cold` and `notcold`) above. The metadata nodes describing the context (e.g., `!2` and `!4` above) are unique ids corresponding to callsites, which can be matched to associated IR calls via [callsite metadata](#md-callsite). In practice these ids are formed via a hash of the callsite’s debug info, and the associated call may be in a different module. The contexts are listed in order from leaf-most call (the allocation itself) to the outermost callsite context required for uniquely identifying the described profile behavior (note this may not be the top of the profiled call stack).

<a id="callsite-metadata"></a>

<a id="md-callsite"></a>

#### ‘`callsite`’ Metadata

The `callsite` metadata is used to identify callsites involved in memory profile contexts described in [memprof metadata](#md-memprof).

It is attached both to the profile allocation calls (see the example in [memprof metadata](#md-memprof)), as well as to other callsites in profiled contexts described in heap allocation `memprof` metadata.

Example:

    %call = call ptr @_Z1Bb(void), !callsite !0
    !0 = !{i64 -6528110295079665978, i64 5462047985461644151}

Each operand in the `callsite` metadata attachment is a unique id corresponding to a callsite (possibly inlined). In practice these ids are formed via a hash of the callsite’s debug info. If the call was not inlined into any callers it will contain a single operand (id). If it was inlined it will contain a list of ids, including the ids of the callsites in the full inline sequence, in order from the leaf-most call’s id to the outermost inlined call.

<a id="noalias-addrspace-metadata"></a>

#### ‘`noalias.addrspace`’ Metadata

The `noalias.addrspace` metadata is used to identify memory operations which cannot access objects allocated in a range of address spaces. It is attached to memory instructions, including [atomicrmw](instructions-memory.md#i-atomicrmw), [cmpxchg](instructions-memory.md#i-cmpxchg), and [call](instructions-other.md#i-call) instructions.

This follows the same form as [range metadata](#range-metadata), except the field entries must be of type `i32`. The interpretation is the same numeric address spaces as applied to IR values.

Example:

    ; %ptr cannot point to an object allocated in addrspace(5)
    %rmw.valid = atomicrmw and ptr %ptr, i64 %value seq_cst, !noalias.addrspace !0

    ; Undefined behavior. The underlying object is allocated in one of the listed
    ; address spaces.
    %alloca = alloca i64, addrspace(5)
    %alloca.cast = addrspacecast ptr addrspace(5) %alloca to ptr
    %rmw.ub = atomicrmw and ptr %alloca.cast, i64 %value seq_cst, !noalias.addrspace !0

    !0 = !{i32 5, i32 6} ; Exclude addrspace(5) only

This is intended for use on targets with a notion of generic address spaces, which at runtime resolve to different physical memory spaces. The interpretation of the address space values is target specific. The behavior is undefined if the runtime memory address does resolve to an object defined in one of the indicated address spaces.

<a id="mmra-metadata"></a>

#### ‘`mmra`’ Metadata

The `mmra` metadata represents target-defined properties on instructions that can be used to selectively relax constraints placed by the memory model.

Refer to [Memory Model Relaxation Annotations](MemoryModelRelaxationAnnotations.html) for more information on how this metadata affects the memory model of a given target.

It is attached to memory instructions such as: [atomicrmw](instructions-memory.md#i-atomicrmw), [cmpxchg](instructions-memory.md#i-cmpxchg), [load](instructions-memory.md#i-load), [store](instructions-memory.md#i-store), [fence](instructions-memory.md#i-fence) and [call](instructions-other.md#i-call) instructions that read or write memory.

The metadata is structured as pairs of strings: a prefix, and suffix that form a MMRA “tag”. The `!mmra` operand can either point to a pair of metadata strings, or a tuple containing multiple pairs of metadata strings.

Example:

    ; Simple pair of strings used directly:
    %rmw.valid = atomicrmw and ptr %ptr, i64 %value seq_cst, !mmra !0

    ; Using multiple pairs of strings using a metadata tuple:
    %rmw.valid = atomicrmw and ptr %ptr, i64 %value seq_cst, !mmra !2

    !0 = !{!"amdgpu-synchronize-as", !"global"}
    !1 = !{!"amdgpu-synchronize-as", !"private"}
    !2 = !{!0, !1}

<a id="nofree-metadata"></a>

#### ‘`nofree`’ Metadata

The `nofree` metadata indicates the memory pointed by the pointer will not be freed after the attached instruction.

<a id="alloc-token-metadata"></a>

#### ‘`alloc_token`’ Metadata

The `alloc_token` metadata may be attached to calls to memory allocation functions, and contains richer semantic information about the type of the allocation. This information is consumed by the `alloc-token` pass to instrument such calls with allocation token IDs.

The metadata contains: string with the type of an allocation, and a boolean denoting if the type contains a pointer.

    call ptr @malloc(i64 64), !alloc_token !0

    !0 = !{!"<type-name>", i1 <contains-pointer>}

<a id="stack-protector-metadata"></a>

#### ‘`stack-protector`’ Metadata

The `stack-protector` metadata may be attached to alloca instructions. An alloca instruction with this metadata and value `i32 0` will be skipped when deciding whether a given function requires a stack protector. The function may still use a stack protector, if other criteria determine it needs one.

The metadata contains an integer, where a 0 value opts the given alloca out of requiring a stack protector.

     %a = alloca [1000 x i8], align 1, !stack-protector !0

    !0 = !{i32 0}

<a id="implicit-ref-metadata"></a>

#### ‘`implicit.ref`’ Metadata

The `implicit.ref` metadata may be attached to a function or global variable definition with a single argument that references a global object. This is typically used when there is some implicit dependence between the symbols that is otherwise opaque to the linker. One such example is metadata which is accessed by a runtime with associated `__start_<section_name>` and `__stop_<section_name>` symbols.

It does not have any effect on non-XCOFF targets.

This metadata lowers to the .ref assembly directive which will add a relocation representing an implicit reference from the section the global belongs to, to the associated symbol. This link will keep the referenced symbol alive if the section is not garbage collected. More than one ref node can be attached to the same function or global variable.

Example:

    @a = global i32 1
    @b = global i32 2
    @c = global i32 3, section "abc", !implicit.ref !0, !implicit.ref !1
    !0 = !{ptr @a}
    !1 = !{ptr @b}

<a id="inline-history-metadata"></a>

#### ‘`inline_history`’ Metadata

The `inline_history` metadata may be attached to a call instruction. It indicates that the call instruction has been inlined from the referenced functions. The call itself should not be inlined if it is a call to any of the referenced functions since that could result in infinite inlining as we continually inline through mutually recursive functions.

This is intended to be added by and used by inliner passes.

The metadata operands must all be function pointers or `null`. `null` can appear when the referenced function is erased from the module, e.g. an internal function that has had all calls to it inlined.

    call void @foo(), !inline_history !0

    !0 = !{ptr @bar, null, ptr @baz}

<a id="elf-section-properties-metadata"></a>

#### ‘`elf_section_properties`’ Metadata

The ‘`elf_section_properties`’ metadata is attached to a function or global variable and is used when writing an object file in ELF format to specify the values of the global’s section type (`sh_type`) and entry size (`sh_entsize`) fields. The first operand specifies the type, and the second operand specifies the entry size.

Example:

    @global = global i32 1, !elf_section_properties !{i32 1879002126, i32 8}

This defines a global with type `SHT_LLVM_CFI_JUMP_TABLE` and entry size 8.
