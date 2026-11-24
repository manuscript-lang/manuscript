[Wiki](../index.md) › [LLVM LangRef](index.md)

# Vector and aggregate operations

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="vector-operations"></a>

### Vector Operations

LLVM supports several instructions to represent vector operations in a target-independent manner. These instructions cover the element-access and vector-specific operations needed to process vectors effectively. While LLVM does directly support these vector operations, many sophisticated algorithms will want to use target-specific intrinsics to take full advantage of a specific target.

<a id="extractelement-instruction"></a>

<a id="i-extractelement"></a>

#### ‘`extractelement`’ Instruction

<a id="id179"></a>

##### Syntax:

    <result> = extractelement <n x <ty>> <val>, <ty2> <idx>  ; yields <ty>
    <result> = extractelement <vscale x n x <ty>> <val>, <ty2> <idx> ; yields <ty>

<a id="id180"></a>

##### Overview:

The ‘`extractelement`’ instruction extracts a single scalar element from a vector at a specified index.

<a id="id181"></a>

##### Arguments:

The first operand of an ‘`extractelement`’ instruction is a value of [vector](type-system.md#t-vector) type. The second operand is an index indicating the position from which to extract the element. The index may be a variable of any integer type, and will be treated as an unsigned integer.

<a id="id182"></a>

##### Semantics:

The result is a scalar of the same type as the element type of `val`. Its value is the value at position `idx` of `val`. If `idx` exceeds the length of `val` for a fixed-length vector, the result is a [poison value](constants.md#poisonvalues). For a scalable vector, if the value of `idx` exceeds the runtime length of the vector, the result is a [poison value](constants.md#poisonvalues).

<a id="id183"></a>

##### Example:

    <result> = extractelement <4 x i32> %vec, i64 0    ; yields i32

<a id="insertelement-instruction"></a>

<a id="i-insertelement"></a>

#### ‘`insertelement`’ Instruction

<a id="id184"></a>

##### Syntax:

    <result> = insertelement <n x <ty>> <val>, <ty> <elt>, <ty2> <idx>    ; yields <n x <ty>>
    <result> = insertelement <vscale x n x <ty>> <val>, <ty> <elt>, <ty2> <idx> ; yields <vscale x n x <ty>>

<a id="id185"></a>

##### Overview:

The ‘`insertelement`’ instruction inserts a scalar element into a vector at a specified index.

<a id="id186"></a>

##### Arguments:

The first operand of an ‘`insertelement`’ instruction is a value of [vector](type-system.md#t-vector) type. The second operand is a scalar value whose type must equal the element type of the first operand. The third operand is an index indicating the position at which to insert the value. The index may be a variable of any integer type, and will be treated as an unsigned integer.

<a id="id187"></a>

##### Semantics:

The result is a vector of the same type as `val`. Its element values are those of `val` except at position `idx`, where it gets the value `elt`. If `idx` exceeds the length of `val` for a fixed-length vector, the result is a [poison value](constants.md#poisonvalues). For a scalable vector, if the value of `idx` exceeds the runtime length of the vector, the result is a [poison value](constants.md#poisonvalues).

<a id="id188"></a>

##### Example:

    <result> = insertelement <4 x i32> %vec, i32 1, i64 0    ; yields <4 x i32>

<a id="shufflevector-instruction"></a>

<a id="i-shufflevector"></a>

#### ‘`shufflevector`’ Instruction

<a id="id189"></a>

##### Syntax:

    <result> = shufflevector <n x <ty>> <v1>, <n x <ty>> <v2>, <m x i32> <mask>    ; yields <m x <ty>>
    <result> = shufflevector <vscale x n x <ty>> <v1>, <vscale x n x <ty>> v2, <vscale x m x i32> <mask>  ; yields <vscale x m x <ty>>

<a id="id190"></a>

##### Overview:

The ‘`shufflevector`’ instruction constructs a permutation of elements from two input vectors, returning a vector with the same element type as the input and length that is the same as the shuffle mask.

<a id="id191"></a>

##### Arguments:

The first two operands of a ‘`shufflevector`’ instruction are vectors with the same type. The third argument is a shuffle mask vector constant whose element type is `i32`. The mask vector elements must be constant integers or `poison` values. The result of the instruction is a vector whose length is the same as the shuffle mask and whose element type is the same as the element type of the first two operands.

<a id="id192"></a>

##### Semantics:

The elements of the two input vectors are numbered from left to right across both of the vectors. For each element of the result vector, the shuffle mask selects an element from one of the input vectors to copy to the result. Non-negative elements in the mask represent an index into the concatenated pair of input vectors.

A `poison` element in the mask vector specifies that the resulting element is `poison`. For backwards-compatibility reasons, LLVM temporarily also accepts `undef` mask elements. These will be interpreted the same way as `poison` mask elements, also producing a `poison` element in the result.

If the shuffle mask selects an `undef` element from one of the input vectors, the resulting element is `undef`.

For scalable vectors, the only valid mask values at present are `zeroinitializer`, `undef` and `poison`, since we cannot write all indices as literals for a vector with a length unknown at compile time.

<a id="id193"></a>

##### Example:

    <result> = shufflevector <4 x i32> %v1, <4 x i32> %v2,
                            <4 x i32> <i32 0, i32 4, i32 1, i32 5>  ; yields <4 x i32>
    <result> = shufflevector <4 x i32> %v1, <4 x i32> poison,
                            <4 x i32> <i32 0, i32 1, i32 2, i32 3>  ; yields <4 x i32> - Identity shuffle.
    <result> = shufflevector <8 x i32> %v1, <8 x i32> poison,
                            <4 x i32> <i32 0, i32 1, i32 2, i32 3>  ; yields <4 x i32>
    <result> = shufflevector <4 x i32> %v1, <4 x i32> %v2,
                            <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7 >  ; yields <8 x i32>

<a id="aggregate-operations"></a>

### Aggregate Operations

LLVM supports several instructions for working with [aggregate](type-system.md#t-aggregate) values.

<a id="extractvalue-instruction"></a>

<a id="i-extractvalue"></a>

#### ‘`extractvalue`’ Instruction

<a id="id194"></a>

##### Syntax:

    <result> = extractvalue <aggregate type> <val>, <idx>{, <idx>}*

<a id="id195"></a>

##### Overview:

The ‘`extractvalue`’ instruction extracts the value of a member field from an [aggregate](type-system.md#t-aggregate) value.

<a id="id196"></a>

##### Arguments:

The first operand of an ‘`extractvalue`’ instruction is a value of [struct](type-system.md#t-struct) or [array](type-system.md#t-array) type. The other operands are constant indices to specify which value to extract in a similar manner as indices in a ‘`getelementptr`’ instruction.

The major differences to `getelementptr` indexing are:

- Since the value being indexed is not a pointer, the first index is omitted and assumed to be zero.

- At least one index must be specified.

- Not only struct indices but also array indices must be in bounds.

<a id="id197"></a>

##### Semantics:

The result is the value at the position in the aggregate specified by the index operands.

<a id="id198"></a>

##### Example:

    <result> = extractvalue {i32, float} %agg, 0    ; yields i32

<a id="insertvalue-instruction"></a>

<a id="i-insertvalue"></a>

#### ‘`insertvalue`’ Instruction

<a id="id199"></a>

##### Syntax:

    <result> = insertvalue <aggregate type> <val>, <ty> <elt>, <idx>{, <idx>}*    ; yields <aggregate type>

<a id="id200"></a>

##### Overview:

The ‘`insertvalue`’ instruction inserts a value into a member field in an [aggregate](type-system.md#t-aggregate) value.

<a id="id201"></a>

##### Arguments:

The first operand of an ‘`insertvalue`’ instruction is a value of [struct](type-system.md#t-struct) or [array](type-system.md#t-array) type. The second operand is a first-class value to insert. The following operands are constant indices indicating the position at which to insert the value in a similar manner as indices in a ‘`extractvalue`’ instruction. The value to insert must have the same type as the value identified by the indices.

<a id="id202"></a>

##### Semantics:

The result is an aggregate of the same type as `val`. Its value is that of `val` except that the value at the position specified by the indices is that of `elt`.

<a id="id203"></a>

##### Example:

    %agg1 = insertvalue {i32, float} poison, i32 1, 0              ; yields {i32 1, float poison}
    %agg2 = insertvalue {i32, float} %agg1, float %val, 1          ; yields {i32 1, float %val}
    %agg3 = insertvalue {i32, {float}} poison, float %val, 1, 0    ; yields {i32 poison, {float %val}}

<a id="debug-records"></a>

<a id="debugrecords"></a>

### Debug Records

Debug records appear interleaved with instructions, but are not instructions; they are used only to define debug information, and have no effect on generated code. They are distinguished from instructions by the use of a leading `#` and an extra level of indentation. As an example:

    %inst1 = op1 %a, %b
      #dbg_value(%inst1, !10, !DIExpression(), !11)
    %inst2 = op2 %inst1, %c

These debug records replace the prior [debug intrinsics](intrinsics-general.md#dbg-intrinsics). Debug records will be disabled if `--experimental-debuginfo-iterators=false` is passed to LLVM; it is an error for both records and intrinsics to appear in the same module. More information about debug records can be found in the [LLVM Source Level Debugging](SourceLevelDebugging.html#format-common-intrinsics) document.
