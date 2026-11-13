[Wiki](../index.md) › [LLVM LangRef](index.md)

# Conversion operations

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="conversion-operations"></a>

### Conversion Operations

The instructions in this category are the conversion instructions (casting) which all take a single operand and a type. They perform various bit conversions on the operand.

<a id="trunc-to-instruction"></a>

<a id="i-trunc"></a>

#### ‘`trunc .. to`’ Instruction

<a id="id239"></a>

##### Syntax:

    <result> = trunc <ty> <value> to <ty2>             ; yields ty2
    <result> = trunc nsw <ty> <value> to <ty2>         ; yields ty2
    <result> = trunc nuw <ty> <value> to <ty2>         ; yields ty2
    <result> = trunc nuw nsw <ty> <value> to <ty2>     ; yields ty2

<a id="id240"></a>

##### Overview:

The ‘`trunc`’ instruction truncates its operand to the type `ty2`.

<a id="id241"></a>

##### Arguments:

The ‘`trunc`’ instruction takes a value to trunc, and a type to trunc it to. Both types must be of [integer](type-system.md#t-integer) types, or vectors of the same number of integers. The bit size of the `value` must be larger than the bit size of the destination type, `ty2`. Equal sized types are not allowed.

<a id="id242"></a>

##### Semantics:

The ‘`trunc`’ instruction truncates the high order bits in `value` and converts the remaining bits to `ty2`. Since the source size must be larger than the destination size, `trunc` cannot be a *no-op cast*. It will always truncate bits.

If the `nuw` keyword is present, and any of the truncated bits are non-zero, the result is a [poison value](constants.md#poisonvalues). If the `nsw` keyword is present, and any of the truncated bits are not the same as the top bit of the truncation result, the result is a [poison value](constants.md#poisonvalues).

<a id="id243"></a>

##### Example:

    %X = trunc i32 257 to i8                        ; yields i8:1
    %Y = trunc i32 123 to i1                        ; yields i1:true
    %Z = trunc i32 122 to i1                        ; yields i1:false
    %W = trunc <2 x i16> <i16 8, i16 7> to <2 x i8> ; yields <i8 8, i8 7>

<a id="zext-to-instruction"></a>

<a id="i-zext"></a>

#### ‘`zext .. to`’ Instruction

<a id="id244"></a>

##### Syntax:

    <result> = zext <ty> <value> to <ty2>             ; yields ty2

<a id="id245"></a>

##### Overview:

The ‘`zext`’ instruction zero extends its operand to type `ty2`.

The `nneg` (non-negative) flag, if present, specifies that the operand is non-negative. This property may be used by optimization passes to later convert the `zext` into a `sext`.

<a id="id246"></a>

##### Arguments:

The ‘`zext`’ instruction takes a value to cast, and a type to cast it to. Both types must be of [integer](type-system.md#t-integer) types, or vectors of the same number of integers. The bit size of the `value` must be smaller than the bit size of the destination type, `ty2`.

<a id="id247"></a>

##### Semantics:

The `zext` fills the high order bits of the `value` with zero bits until it reaches the size of the destination type, `ty2`.

When zero extending from i1, the result will always be either 0 or 1.

If the `nneg` flag is set, and the `zext` argument is negative, the result is a poison value.

<a id="id248"></a>

##### Example:

    %X = zext i32 257 to i64              ; yields i64:257
    %Y = zext i1 true to i32              ; yields i32:1
    %Z = zext <2 x i16> <i16 8, i16 7> to <2 x i32> ; yields <i32 8, i32 7>

    %a = zext nneg i8 127 to i16 ; yields i16 127
    %b = zext nneg i8 -1 to i16  ; yields i16 poison

<a id="sext-to-instruction"></a>

<a id="i-sext"></a>

#### ‘`sext .. to`’ Instruction

<a id="id249"></a>

##### Syntax:

    <result> = sext <ty> <value> to <ty2>             ; yields ty2

<a id="id250"></a>

##### Overview:

The ‘`sext`’ sign extends `value` to the type `ty2`.

<a id="id251"></a>

##### Arguments:

The ‘`sext`’ instruction takes a value to cast, and a type to cast it to. Both types must be of [integer](type-system.md#t-integer) types, or vectors of the same number of integers. The bit size of the `value` must be smaller than the bit size of the destination type, `ty2`.

<a id="id252"></a>

##### Semantics:

The ‘`sext`’ instruction performs a sign extension by copying the sign bit (highest order bit) of the `value` until it reaches the bit size of the type `ty2`.

When sign extending from i1, the extension always results in -1 or 0.

<a id="id253"></a>

##### Example:

    %X = sext i8  -1 to i16              ; yields i16   :65535
    %Y = sext i1 true to i32             ; yields i32:-1
    %Z = sext <2 x i16> <i16 8, i16 7> to <2 x i32> ; yields <i32 8, i32 7>

<a id="fptrunc-to-instruction"></a>

<a id="i-fptrunc"></a>

#### ‘`fptrunc .. to`’ Instruction

<a id="id254"></a>

##### Syntax:

    <result> = fptrunc [fast-math flags]* <ty> <value> to <ty2> ; yields ty2

<a id="id255"></a>

##### Overview:

The ‘`fptrunc`’ instruction truncates `value` to type `ty2`.

<a id="id256"></a>

##### Arguments:

The ‘`fptrunc`’ instruction takes a [floating-point](type-system.md#t-floating) value to cast and a [floating-point](type-system.md#t-floating) type to cast it to. The size of `value` must be larger than the size of `ty2`. This implies that `fptrunc` cannot be used to make a *no-op cast*.

<a id="id257"></a>

##### Semantics:

The ‘`fptrunc`’ instruction casts a `value` from a larger [floating-point](type-system.md#t-floating) type to a smaller [floating-point](type-system.md#t-floating) type. This instruction is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv).

NaN values follow the usual [NaN behaviors](high-level-structure.md#floatnan), except that *if* a NaN payload is propagated from the input (“Quieting NaN propagation” or “Unchanged NaN propagation” cases), then the low order bits of the NaN payload which cannot fit in the resulting type are discarded. Note that if discarding the low order bits leads to an all-0 payload, this cannot be represented as a signaling NaN (it would represent an infinity instead), so in that case “Unchanged NaN propagation” is not possible.

This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations.

<a id="id258"></a>

##### Example:

    %X = fptrunc double 16777217.0 to float    ; yields float:16777216.0
    %Y = fptrunc double 1.0E+300 to half       ; yields half:+infinity

<a id="fpext-to-instruction"></a>

<a id="i-fpext"></a>

#### ‘`fpext .. to`’ Instruction

<a id="id259"></a>

##### Syntax:

    <result> = fpext [fast-math flags]* <ty> <value> to <ty2> ; yields ty2

<a id="id260"></a>

##### Overview:

The ‘`fpext`’ extends a floating-point `value` to a larger floating-point value.

<a id="id261"></a>

##### Arguments:

The ‘`fpext`’ instruction takes a [floating-point](type-system.md#t-floating) `value` to cast, and a [floating-point](type-system.md#t-floating) type to cast it to. The source type must be smaller than the destination type.

<a id="id262"></a>

##### Semantics:

The ‘`fpext`’ instruction extends the `value` from a smaller [floating-point](type-system.md#t-floating) type to a larger [floating-point](type-system.md#t-floating) type. The `fpext` cannot be used to make a *no-op cast* because it always changes bits. Use `bitcast` to make a *no-op cast* for a floating-point cast.

NaN values follow the usual [NaN behaviors](high-level-structure.md#floatnan), except that *if* a NaN payload is propagated from the input (“Quieting NaN propagation” or “Unchanged NaN propagation” cases), then it is copied to the high order bits of the resulting payload, and the remaining low order bits are zero.

This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations.

<a id="id263"></a>

##### Example:

    %X = fpext float 3.125 to double         ; yields double:3.125000e+00
    %Y = fpext double %X to fp128            ; yields fp128:0xL00000000000000004000900000000000

<a id="fptoui-to-instruction"></a>

#### ‘`fptoui .. to`’ Instruction

<a id="id264"></a>

##### Syntax:

    <result> = fptoui <ty> <value> to <ty2>             ; yields ty2

<a id="id265"></a>

##### Overview:

The ‘`fptoui`’ converts a floating-point `value` to its unsigned integer equivalent of type `ty2`.

<a id="id266"></a>

##### Arguments:

The ‘`fptoui`’ instruction takes a value to cast, which must be a scalar or vector [floating-point](type-system.md#t-floating) value, and a type to cast it to `ty2`, which must be an [integer](type-system.md#t-integer) type. If `ty` is a vector floating-point type, `ty2` must be a vector integer type with the same number of elements as `ty`

<a id="id267"></a>

##### Semantics:

The ‘`fptoui`’ instruction converts its [floating-point](type-system.md#t-floating) operand into the nearest (rounding towards zero) unsigned integer value. If the value cannot fit in `ty2`, the result is a [poison value](constants.md#poisonvalues).

<a id="id268"></a>

##### Example:

    %X = fptoui double 123.0 to i32      ; yields i32:123
    %Y = fptoui float 1.0E+300 to i1     ; yields undefined:1
    %Z = fptoui float 1.04E+17 to i8     ; yields undefined:1

<a id="fptosi-to-instruction"></a>

#### ‘`fptosi .. to`’ Instruction

<a id="id269"></a>

##### Syntax:

    <result> = fptosi <ty> <value> to <ty2>             ; yields ty2

<a id="id270"></a>

##### Overview:

The ‘`fptosi`’ instruction converts [floating-point](type-system.md#t-floating) `value` to type `ty2`.

<a id="id271"></a>

##### Arguments:

The ‘`fptosi`’ instruction takes a value to cast, which must be a scalar or vector [floating-point](type-system.md#t-floating) value, and a type to cast it to `ty2`, which must be an [integer](type-system.md#t-integer) type. If `ty` is a vector floating-point type, `ty2` must be a vector integer type with the same number of elements as `ty`

<a id="id272"></a>

##### Semantics:

The ‘`fptosi`’ instruction converts its [floating-point](type-system.md#t-floating) operand into the nearest (rounding towards zero) signed integer value. If the value cannot fit in `ty2`, the result is a [poison value](constants.md#poisonvalues).

<a id="id273"></a>

##### Example:

    %X = fptosi double -123.0 to i32      ; yields i32:-123
    %Y = fptosi float 1.0E-247 to i1      ; yields undefined:1
    %Z = fptosi float 1.04E+17 to i8      ; yields undefined:1

<a id="uitofp-to-instruction"></a>

<a id="i-uitofp"></a>

#### ‘`uitofp .. to`’ Instruction

<a id="id274"></a>

##### Syntax:

    <result> = uitofp [fast-math flags]* [nneg] <ty> <value> to <ty2> ; yields ty2

<a id="id275"></a>

##### Overview:

The ‘`uitofp`’ instruction regards `value` as an unsigned integer and converts that value to the `ty2` type.

The `nneg` (non-negative) flag, if present, specifies that the operand is non-negative. This property may be used by optimization passes to later convert the `uitofp` into a `sitofp`.

<a id="id276"></a>

##### Arguments:

The ‘`uitofp`’ instruction takes a value to cast, which must be a scalar or vector [integer](type-system.md#t-integer) value, and a type to cast it to `ty2`, which must be an [floating-point](type-system.md#t-floating) type. If `ty` is a vector integer type, `ty2` must be a vector floating-point type with the same number of elements as `ty`

<a id="id277"></a>

##### Semantics:

The ‘`uitofp`’ instruction interprets its operand as an unsigned integer quantity and converts it to the corresponding floating-point value. If the value cannot be exactly represented, it is rounded using the default rounding mode.

If the `nneg` flag is set, and the `uitofp` argument is negative, the result is a poison value.

If the ‘`nsz`’ flag is set and the input value is 0, the sign bit of the result is non-deterministic.

<a id="id278"></a>

##### Example:

    %X = uitofp i32 257 to float         ; yields float:257.0
    %Y = uitofp i8 -1 to double          ; yields double:255.0

    %a = uitofp nneg i32 256 to float    ; yields float:256.0
    %b = uitofp nneg i32 -256 to float   ; yields float poison

<a id="sitofp-to-instruction"></a>

<a id="i-sitofp"></a>

#### ‘`sitofp .. to`’ Instruction

<a id="id279"></a>

##### Syntax:

    <result> = sitofp [fast-math flags]* <ty> <value> to <ty2> ; yields ty2

<a id="id280"></a>

##### Overview:

The ‘`sitofp`’ instruction regards `value` as a signed integer and converts that value to the `ty2` type.

<a id="id281"></a>

##### Arguments:

The ‘`sitofp`’ instruction takes a value to cast, which must be a scalar or vector [integer](type-system.md#t-integer) value, and a type to cast it to `ty2`, which must be an [floating-point](type-system.md#t-floating) type. If `ty` is a vector integer type, `ty2` must be a vector floating-point type with the same number of elements as `ty`

<a id="id282"></a>

##### Semantics:

The ‘`sitofp`’ instruction interprets its operand as a signed integer quantity and converts it to the corresponding floating-point value. If the value cannot be exactly represented, it is rounded using the default rounding mode.

If the ‘`nsz`’ flag is set and the input value is 0, the sign bit of the result is non-deterministic.

<a id="id283"></a>

##### Example:

    %X = sitofp i32 257 to float         ; yields float:257.0
    %Y = sitofp i8 -1 to double          ; yields double:-1.0

<a id="ptrtoint-to-instruction"></a>

<a id="i-ptrtoint"></a>

#### ‘`ptrtoint .. to`’ Instruction

<a id="id284"></a>

##### Syntax:

    <result> = ptrtoint <ty> <value> to <ty2>             ; yields ty2

<a id="id285"></a>

##### Overview:

The ‘`ptrtoint`’ instruction converts the pointer or a vector of pointers `value` to the integer (or vector of integers) type `ty2`.

<a id="id286"></a>

##### Arguments:

The ‘`ptrtoint`’ instruction takes a `value` to cast, which must be a value of type [pointer](type-system.md#t-pointer) or a vector of pointers, and a type to cast it to `ty2`, which must be an [integer](type-system.md#t-integer) or a vector of integers type.

<a id="id287"></a>

##### Semantics:

The ‘`ptrtoint`’ instruction converts `value` to integer type `ty2` by interpreting all the pointer representation bits as an integer (equivalent to a `bitcast`) and either truncating or zero extending that value to the size of the integer type. If `value` is smaller than `ty2` then a zero extension is done. If `value` is larger than `ty2` then a truncation is done. If they are the same size, then nothing is done (*no-op cast*) other than a type change. The `ptrtoint` always [captures address and provenance](high-level-structure.md#pointercapture) of the pointer argument.

<a id="id288"></a>

##### Example:

    %X = ptrtoint ptr %P to i8                         ; yields truncation on 32-bit architecture
    %Y = ptrtoint ptr %P to i64                        ; yields zero extension on 32-bit architecture
    %Z = ptrtoint <4 x ptr> %P to <4 x i64>; yields vector zero extension for a vector of addresses on 32-bit architecture

<a id="ptrtoaddr-to-instruction"></a>

<a id="i-ptrtoaddr"></a>

#### ‘`ptrtoaddr .. to`’ Instruction

<a id="id289"></a>

##### Syntax:

    <result> = ptrtoaddr <ty> <value> to <ty2>             ; yields ty2

<a id="id290"></a>

##### Overview:

The ‘`ptrtoaddr`’ instruction converts the pointer or a vector of pointers `value` to the underlying integer address (or vector of addresses) of type `ty2`. This is different from [ptrtoint](#i-ptrtoint) in that it only operates on the index bits of the pointer and ignores all other bits, and does not capture the provenance of the pointer.

<a id="id291"></a>

##### Arguments:

The ‘`ptrtoaddr`’ instruction takes a `value` to cast, which must be a value of type [pointer](type-system.md#t-pointer) or a vector of pointers, and a type to cast it to `ty2`, which must be must be the [integer](type-system.md#t-integer) type (or vector of integers) matching the pointer index width of the address space of `ty`.

<a id="id292"></a>

##### Semantics:

The ‘`ptrtoaddr`’ instruction converts `value` to integer type `ty2` by interpreting the lowest index-width pointer representation bits as an integer. If the address size and the pointer representation size are the same and `value` and `ty2` are the same size, then nothing is done (*no-op cast*) other than a type change.

The `ptrtoaddr` instruction always [captures the address but not the provenance](high-level-structure.md#pointercapture) of the pointer argument.

<a id="id293"></a>

##### Example:

This example assumes pointers in address space 1 are 64 bits in size with an address width of 32 bits (`p1:64:64:64:32` [datalayout string](high-level-structure.md#langref-datalayout))

    %X = ptrtoaddr ptr addrspace(1) %P to i32              ; extracts low 32 bits of pointer
    %Y = ptrtoaddr <4 x ptr addrspace(1)> %P to <4 x i32>  ; yields vector of low 32 bits for each pointer

<a id="inttoptr-to-instruction"></a>

<a id="i-inttoptr"></a>

#### ‘`inttoptr .. to`’ Instruction

<a id="id294"></a>

##### Syntax:

    <result> = inttoptr <ty> <value> to <ty2>[, !dereferenceable !<deref_bytes_node>][, !dereferenceable_or_null !<deref_bytes_node>][, !nofree !<empty_node>]            ; yields ty2

<a id="id295"></a>

##### Overview:

The ‘`inttoptr`’ instruction converts an integer `value` to a pointer type, `ty2`.

<a id="id296"></a>

##### Arguments:

The ‘`inttoptr`’ instruction takes an [integer](type-system.md#t-integer) value to cast, and a type to cast it to, which must be a [pointer](type-system.md#t-pointer) type.

The optional `!dereferenceable` metadata must reference a single metadata name `<deref_bytes_node>` corresponding to a metadata node with one `i64` entry. See `dereferenceable` metadata.

The optional `!dereferenceable_or_null` metadata must reference a single metadata name `<deref_bytes_node>` corresponding to a metadata node with one `i64` entry. See `dereferenceable_or_null` metadata.

The optional `!nofree` metadata must reference a single metadata name `<empty_node>` corresponding to a metadata node with no entries. The existence of the `!nofree` metadata on the instruction tells the optimizer that the memory pointed by the pointer will not be freed after this point.

<a id="id297"></a>

##### Semantics:

The ‘`inttoptr`’ instruction converts `value` to type `ty2` by applying either a zero extension or a truncation depending on the size of the integer `value`. If `value` is larger than the size of a pointer then a truncation is done. If `value` is smaller than the size of a pointer then a zero extension is done. If they are the same size, nothing is done (*no-op cast*). The behavior is equivalent to a `bitcast`, however, the resulting value is not guaranteed to be dereferenceable (e.g., if the result type is a [non-integral pointers](high-level-structure.md#nointptrtype)).

<a id="id298"></a>

##### Example:

    %X = inttoptr i32 255 to ptr           ; yields zero extension on 64-bit architecture
    %Y = inttoptr i32 255 to ptr           ; yields no-op on 32-bit architecture
    %Z = inttoptr i64 0 to ptr             ; yields truncation on 32-bit architecture
    %Z = inttoptr <4 x i32> %G to <4 x ptr>; yields truncation of vector G to four pointers

<a id="bitcast-to-instruction"></a>

<a id="i-bitcast"></a>

#### ‘`bitcast .. to`’ Instruction

<a id="id299"></a>

##### Syntax:

    <result> = bitcast <ty> <value> to <ty2>             ; yields ty2

<a id="id300"></a>

##### Overview:

The ‘`bitcast`’ instruction converts `value` to type `ty2` without changing any bits.

<a id="id301"></a>

##### Arguments:

The ‘`bitcast`’ instruction takes a value to cast, which must be a non-aggregate first class value, and a type to cast it to, which must also be a non-aggregate [first class](type-system.md#t-firstclass) type. The bit sizes of `value` and the destination type, `ty2`, must be identical. If the source type is a pointer, the destination type must also be a pointer or a byte (vector of bytes) of the same size. This instruction supports bitwise conversion of vectors to integers and to vectors of other types (as long as they have the same size).

<a id="id302"></a>

##### Semantics:

The ‘`bitcast`’ instruction converts `value` to type `ty2`. It is always a *no-op cast* because no bits change with this conversion. The conversion is done as if the `value` had been stored to memory and read back as type `ty2`. Pointer (or vector of pointers) types may only be converted to other pointer (or vector of pointers) types with the same address space or byte (or vector of bytes) types through this instruction. To convert pointers to other types, use the [inttoptr](#i-inttoptr) or [ptrtoint](#i-ptrtoint) instructions first.

There is a caveat for bitcasts involving vector types in relation to endianness. For example `bitcast <2 x i8> <value> to i16` puts element zero of the vector in the least significant bits of the i16 for little-endian while element zero ends up in the most significant bits for big-endian.

If `value` is of the [byte type](type-system.md#t-byte):

- If `ty2` is a scalar type:

  - If `ty2` is a byte type, the original bits are unchanged.

  - If `ty2` is a pointer type:

    - If at least one bit of `value` is `poison`, the result is `poison`.

    - If all bits of `value` are from the same pointer and are correctly ordered (there were no pointer bit swaps), the result is that pointer.

    - Otherwise, the result is a pointer with the address given by the integer value of the input, and without provenance.

  - If `ty2` is an integer or floating-point type:

    - If at least one bit of `value` is `poison`, the result is `poison`.

    - Otherwise, the result is the value encoded by the input bits with their provenance stripped without being exposed.

- If `ty2` is a vector type, the input bits get sliced into chunks corresponding to lanes of the output. Each lane is then converted using the rules for scalar types above.

<a id="id303"></a>

##### Example:

    %X = bitcast i8 255 to i8         ; yields i8 :-1
    %Y = bitcast i32* %x to i16*      ; yields i16*:%x
    %Z = bitcast <2 x i32> %V to i64; ; yields i64: %V (depends on endianness)
    %Z = bitcast <2 x i32*> %V to <2 x i64*> ; yields <2 x i64*>

    ; considering %bi to hold an integer and %bp to hold a pointer,
    %a = bitcast b64 %bi to i64       ; returns an integer, no-op cast
    %b = bitcast b64 %bp to i64       ; reinterprets the pointer as an integer, returning its address without exposing provenance
    %c = bitcast b64 %bp to ptr       ; returns a pointer, no-op cast
    %d = bitcast b64 %bi to ptr       ; reinterprets the integer as a pointer, returning a pointer with no provenance

    %e = bitcast <2 x b32> %v to i64  ; reinterprets the raw bytes as an integer
    %f = bitcast <2 x b32> %v to ptr  ; reinterprets the raw bytes as a pointer

    %g = bitcast <2 x b32> %v to <4 x i16> ; reinterprets the raw bytes as integers

<a id="addrspacecast-to-instruction"></a>

<a id="i-addrspacecast"></a>

#### ‘`addrspacecast .. to`’ Instruction

<a id="id304"></a>

##### Syntax:

    <result> = addrspacecast <pty> <ptrval> to <pty2>       ; yields pty2

<a id="id305"></a>

##### Overview:

The ‘`addrspacecast`’ instruction converts `ptrval` from `pty` in address space `n` to type `pty2` in address space `m`.

<a id="id306"></a>

##### Arguments:

The ‘`addrspacecast`’ instruction takes a pointer or vector of pointer value to cast and a pointer type to cast it to, which must have a different address space.

<a id="id307"></a>

##### Semantics:

The ‘`addrspacecast`’ instruction converts the pointer value `ptrval` to type `pty2`. It can be a *no-op cast* or a complex value modification, depending on the target and the address space pair. Pointer conversions within the same address space must be performed with the `bitcast` instruction. Note that if the address space conversion produces a dereferenceable result then both result and operand refer to the same memory location. The conversion must have no side effects, and must not capture the value of the pointer.

If the source is [poison](constants.md#poisonvalues), the result is [poison](constants.md#poisonvalues).

If the source is not [poison](constants.md#poisonvalues), and both source and destination are [integral pointers](high-level-structure.md#nointptrtype), and the result pointer is dereferenceable, the cast is assumed to be reversible (i.e., casting the result back to the original address space should yield the original bit pattern).

Which address space casts are supported depends on the target. Unsupported address space casts return [poison](constants.md#poisonvalues).

<a id="id308"></a>

##### Example:

    %X = addrspacecast ptr %x to ptr addrspace(1)
    %Y = addrspacecast ptr addrspace(1) %y to ptr addrspace(2)
    %Z = addrspacecast <4 x ptr> %z to <4 x ptr addrspace(3)>
