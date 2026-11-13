[Wiki](../index.md) › [LLVM LangRef](index.md)

# Intrinsics: libc, bit and arithmetic

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="standard-c-c-library-intrinsics"></a>

### Standard C/C++ Library Intrinsics

LLVM provides intrinsics for a few important standard C/C++ library functions. These intrinsics allow source-language front-ends to pass information about the alignment of the pointer arguments to the code generator, providing opportunity for more efficient code generation.

<a id="llvm-abs-intrinsic"></a>

<a id="int-abs"></a>

#### ‘`llvm.abs.*`’ Intrinsic

<a id="id516"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.abs` on any integer bit width or any vector of integer elements.

    declare i32 @llvm.abs.i32(i32 <src>, i1 <is_int_min_poison>)
    declare <4 x i32> @llvm.abs.v4i32(<4 x i32> <src>, i1 <is_int_min_poison>)

<a id="id517"></a>

##### Overview:

The ‘`llvm.abs`’ family of intrinsic functions returns the absolute value of an argument.

<a id="id518"></a>

##### Arguments:

The first argument is the value for which the absolute value is to be returned. This argument may be of any integer type or a vector with integer element type. The return type must match the first argument type.

The second argument must be a constant and is a flag to indicate whether the result value of the ‘`llvm.abs`’ intrinsic is a [poison value](constants.md#poisonvalues) if the first argument is statically or dynamically an `INT_MIN` value.

<a id="id519"></a>

##### Semantics:

The ‘`llvm.abs`’ intrinsic returns the magnitude (always positive) of the first argument or each element of a vector argument.”. If the first argument is `INT_MIN`, then the result is also `INT_MIN` if `is_int_min_poison == 0` and `poison` otherwise.

<a id="llvm-smax-intrinsic"></a>

<a id="int-smax"></a>

#### ‘`llvm.smax.*`’ Intrinsic

<a id="id520"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `@llvm.smax` on any integer bit width or any vector of integer elements.

    declare i32 @llvm.smax.i32(i32 %a, i32 %b)
    declare <4 x i32> @llvm.smax.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id521"></a>

##### Overview:

Return the larger of `%a` and `%b` comparing the values as signed integers. Vector intrinsics operate on a per-element basis. The larger element of `%a` and `%b` at a given index is returned for that index.

<a id="id522"></a>

##### Arguments:

The arguments (`%a` and `%b`) may be of any integer type or a vector with integer element type. The argument types must match each other, and the return type must match the argument type.

<a id="llvm-smin-intrinsic"></a>

<a id="int-smin"></a>

#### ‘`llvm.smin.*`’ Intrinsic

<a id="id523"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `@llvm.smin` on any integer bit width or any vector of integer elements.

    declare i32 @llvm.smin.i32(i32 %a, i32 %b)
    declare <4 x i32> @llvm.smin.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id524"></a>

##### Overview:

Return the smaller of `%a` and `%b` comparing the values as signed integers. Vector intrinsics operate on a per-element basis. The smaller element of `%a` and `%b` at a given index is returned for that index.

<a id="id525"></a>

##### Arguments:

The arguments (`%a` and `%b`) may be of any integer type or a vector with integer element type. The argument types must match each other, and the return type must match the argument type.

<a id="llvm-umax-intrinsic"></a>

<a id="int-umax"></a>

#### ‘`llvm.umax.*`’ Intrinsic

<a id="id526"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `@llvm.umax` on any integer bit width or any vector of integer elements.

    declare i32 @llvm.umax.i32(i32 %a, i32 %b)
    declare <4 x i32> @llvm.umax.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id527"></a>

##### Overview:

Return the larger of `%a` and `%b` comparing the values as unsigned integers. Vector intrinsics operate on a per-element basis. The larger element of `%a` and `%b` at a given index is returned for that index.

<a id="id528"></a>

##### Arguments:

The arguments (`%a` and `%b`) may be of any integer type or a vector with integer element type. The argument types must match each other, and the return type must match the argument type.

<a id="llvm-umin-intrinsic"></a>

<a id="int-umin"></a>

#### ‘`llvm.umin.*`’ Intrinsic

<a id="id529"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `@llvm.umin` on any integer bit width or any vector of integer elements.

    declare i32 @llvm.umin.i32(i32 %a, i32 %b)
    declare <4 x i32> @llvm.umin.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id530"></a>

##### Overview:

Return the smaller of `%a` and `%b` comparing the values as unsigned integers. Vector intrinsics operate on a per-element basis. The smaller element of `%a` and `%b` at a given index is returned for that index.

<a id="id531"></a>

##### Arguments:

The arguments (`%a` and `%b`) may be of any integer type or a vector with integer element type. The argument types must match each other, and the return type must match the argument type.

<a id="llvm-scmp-intrinsic"></a>

<a id="int-scmp"></a>

#### ‘`llvm.scmp.*`’ Intrinsic

<a id="id532"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `@llvm.scmp` on any integer bit width or any vector of integer elements.

    declare i2 @llvm.scmp.i2.i32(i32 %a, i32 %b)
    declare <4 x i32> @llvm.scmp.v4i32.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id533"></a>

##### Overview:

Return `-1` if `%a` is signed less than `%b`, `0` if they are equal, and `1` if `%a` is signed greater than `%b`. Vector intrinsics operate on a per-element basis.

<a id="id534"></a>

##### Arguments:

The arguments (`%a` and `%b`) may be of any integer type or a vector with integer element type. The argument types must match each other, and the return type must be at least as wide as `i2`, to hold the three possible return values.

<a id="llvm-ucmp-intrinsic"></a>

<a id="int-ucmp"></a>

#### ‘`llvm.ucmp.*`’ Intrinsic

<a id="id535"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `@llvm.ucmp` on any integer bit width or any vector of integer elements.

    declare i2 @llvm.ucmp.i2.i32(i32 %a, i32 %b)
    declare <4 x i32> @llvm.ucmp.v4i32.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id536"></a>

##### Overview:

Return `-1` if `%a` is unsigned less than `%b`, `0` if they are equal, and `1` if `%a` is unsigned greater than `%b`. Vector intrinsics operate on a per-element basis.

<a id="id537"></a>

##### Arguments:

The arguments (`%a` and `%b`) may be of any integer type or a vector with integer element type. The argument types must match each other, and the return type must be at least as wide as `i2`, to hold the three possible return values.

<a id="llvm-memcpy-intrinsic"></a>

<a id="int-memcpy"></a>

#### ‘`llvm.memcpy`’ Intrinsic

<a id="id538"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memcpy` on any integer bit width and for different address spaces. Not all targets support all bit widths however.

    declare void @llvm.memcpy.p0.p0.i32(ptr <dest>, ptr <src>,
                                        i32 <len>, i1 <isvolatile>)
    declare void @llvm.memcpy.p0.p0.i64(ptr <dest>, ptr <src>,
                                        i64 <len>, i1 <isvolatile>)

<a id="id539"></a>

##### Overview:

The ‘`llvm.memcpy.*`’ intrinsics copy a block of memory from the source location to the destination location.

Note that, unlike the standard libc function, the `llvm.memcpy.*` intrinsics do not return a value, takes extra isvolatile arguments and the pointers can be in specified address spaces.

<a id="id540"></a>

##### Arguments:

The first argument is a pointer to the destination, the second is a pointer to the source. The third argument is an integer argument specifying the number of bytes to copy, and the fourth is a boolean indicating a volatile access.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first and second arguments.

If the `isvolatile` parameter is `true`, the `llvm.memcpy` call is a [volatile operation](high-level-structure.md#volatile). The detailed access behavior is not very cleanly specified and it is unwise to depend on it.

<a id="id541"></a>

##### Semantics:

The ‘`llvm.memcpy.*`’ intrinsics copy a block of memory from the source location to the destination location, which must either be equal or non-overlapping. It copies “len” bytes of memory over. If the argument is known to be aligned to some boundary, this can be specified as an attribute on the argument.

If `<len>` is 0, it is no-op modulo the behavior of attributes attached to the arguments. If `<len>` is not a well-defined value, the behavior is undefined. If `<len>` is not zero, both `<dest>` and `<src>` should be well-defined, otherwise the behavior is undefined.

<a id="llvm-memcpy-inline-intrinsic"></a>

<a id="int-memcpy-inline"></a>

#### ‘`llvm.memcpy.inline`’ Intrinsic

<a id="id542"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memcpy.inline` on any integer bit width and for different address spaces. Not all targets support all bit widths however.

    declare void @llvm.memcpy.inline.p0.p0.i32(ptr <dest>, ptr <src>,
                                               i32 <len>, i1 <isvolatile>)
    declare void @llvm.memcpy.inline.p0.p0.i64(ptr <dest>, ptr <src>,
                                               i64 <len>, i1 <isvolatile>)

<a id="id543"></a>

##### Overview:

The ‘`llvm.memcpy.inline.*`’ intrinsics copy a block of memory from the source location to the destination location and guarantees that no external functions are called.

Note that, unlike the standard libc function, the `llvm.memcpy.inline.*` intrinsics do not return a value, takes extra isvolatile arguments and the pointers can be in specified address spaces.

<a id="id544"></a>

##### Arguments:

The first argument is a pointer to the destination, the second is a pointer to the source. The third argument is an integer argument specifying the number of bytes to copy, and the fourth is a boolean indicating a volatile access.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first and second arguments.

If the `isvolatile` parameter is `true`, the `llvm.memcpy.inline` call is a [volatile operation](high-level-structure.md#volatile). The detailed access behavior is not very cleanly specified and it is unwise to depend on it.

<a id="id545"></a>

##### Semantics:

The ‘`llvm.memcpy.inline.*`’ intrinsics copy a block of memory from the source location to the destination location, which are not allowed to overlap. It copies “len” bytes of memory over. If the argument is known to be aligned to some boundary, this can be specified as an attribute on the argument. The behavior of ‘`llvm.memcpy.inline.*`’ is equivalent to the behavior of ‘`llvm.memcpy.*`’, but the generated code is guaranteed not to call any external functions.

<a id="llvm-memmove-intrinsic"></a>

<a id="int-memmove"></a>

#### ‘`llvm.memmove`’ Intrinsic

<a id="id546"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memmove` on any integer bit width and for different address space. Not all targets support all bit widths however.

    declare void @llvm.memmove.p0.p0.i32(ptr <dest>, ptr <src>,
                                         i32 <len>, i1 <isvolatile>)
    declare void @llvm.memmove.p0.p0.i64(ptr <dest>, ptr <src>,
                                         i64 <len>, i1 <isvolatile>)

<a id="id547"></a>

##### Overview:

The ‘`llvm.memmove.*`’ intrinsics move a block of memory from the source location to the destination location. It is similar to the ‘`llvm.memcpy`’ intrinsic but allows the two memory locations to overlap.

Note that, unlike the standard libc function, the `llvm.memmove.*` intrinsics do not return a value, takes an extra isvolatile argument and the pointers can be in specified address spaces.

<a id="id548"></a>

##### Arguments:

The first argument is a pointer to the destination, the second is a pointer to the source. The third argument is an integer argument specifying the number of bytes to copy, and the fourth is a boolean indicating a volatile access.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first and second arguments.

If the `isvolatile` parameter is `true`, the `llvm.memmove` call is a [volatile operation](high-level-structure.md#volatile). The detailed access behavior is not very cleanly specified and it is unwise to depend on it.

<a id="id549"></a>

##### Semantics:

The ‘`llvm.memmove.*`’ intrinsics copy a block of memory from the source location to the destination location, which may overlap. It copies “len” bytes of memory over. If the argument is known to be aligned to some boundary, this can be specified as an attribute on the argument.

If `<len>` is 0, it is no-op modulo the behavior of attributes attached to the arguments. If `<len>` is not a well-defined value, the behavior is undefined. If `<len>` is not zero, both `<dest>` and `<src>` should be well-defined, otherwise the behavior is undefined.

<a id="llvm-memset-intrinsics"></a>

<a id="int-memset"></a>

#### ‘`llvm.memset.*`’ Intrinsics

<a id="id550"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memset` on any integer bit width and for different address spaces. However, not all targets support all bit widths.

    declare void @llvm.memset.p0.i32(ptr <dest>, i8 <val>,
                                     i32 <len>, i1 <isvolatile>)
    declare void @llvm.memset.p0.i64(ptr <dest>, i8 <val>,
                                     i64 <len>, i1 <isvolatile>)

<a id="id551"></a>

##### Overview:

The ‘`llvm.memset.*`’ intrinsics fill a block of memory with a particular byte value.

Note that, unlike the standard libc function, the `llvm.memset` intrinsic does not return a value and takes an extra volatile argument. Also, the destination can be in an arbitrary address space.

<a id="id552"></a>

##### Arguments:

The first argument is a pointer to the destination to fill, the second is the byte value with which to fill it, the third argument is an integer argument specifying the number of bytes to fill, and the fourth is a boolean indicating a volatile access.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first arguments.

If the `isvolatile` parameter is `true`, the `llvm.memset` call is a [volatile operation](high-level-structure.md#volatile). The detailed access behavior is not very cleanly specified and it is unwise to depend on it.

<a id="id553"></a>

##### Semantics:

The ‘`llvm.memset.*`’ intrinsics fill “len” bytes of memory starting at the destination location. If the argument is known to be aligned to some boundary, this can be specified as an attribute on the argument.

If `<len>` is 0, it is no-op modulo the behavior of attributes attached to the arguments. If `<len>` is not a well-defined value, the behavior is undefined. If `<len>` is not zero, `<dest>` should be well-defined, otherwise the behavior is undefined.

<a id="llvm-memset-inline-intrinsic"></a>

<a id="int-memset-inline"></a>

#### ‘`llvm.memset.inline`’ Intrinsic

<a id="id554"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memset.inline` on any integer bit width and for different address spaces. Not all targets support all bit widths however.

    declare void @llvm.memset.inline.p0.i32(ptr <dest>, i8 <val>,
                                            i32 <len>, i1 <isvolatile>)
    declare void @llvm.memset.inline.p0.i64(ptr <dest>, i8 <val>,
                                            i64 <len>, i1 <isvolatile>)

<a id="id555"></a>

##### Overview:

The ‘`llvm.memset.inline.*`’ intrinsics fill a block of memory with a particular byte value and guarantees that no external functions are called.

Note that, unlike the standard libc function, the `llvm.memset.inline.*` intrinsics do not return a value, take an extra isvolatile argument and the pointer can be in specified address spaces.

<a id="id556"></a>

##### Arguments:

The first argument is a pointer to the destination to fill, the second is the byte value with which to fill it, the third argument is an integer argument specifying the number of bytes to fill, and the fourth is a boolean indicating a volatile access.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first argument.

If the `isvolatile` parameter is `true`, the `llvm.memset.inline` call is a [volatile operation](high-level-structure.md#volatile). The detailed access behavior is not very cleanly specified and it is unwise to depend on it.

<a id="id557"></a>

##### Semantics:

The ‘`llvm.memset.inline.*`’ intrinsics fill “len” bytes of memory starting at the destination location. If the argument is known to be aligned to some boundary, this can be specified as an attribute on the argument.

If `<len>` is 0, it is no-op modulo the behavior of attributes attached to the arguments. If `<len>` is not a well-defined value, the behavior is undefined. If `<len>` is not zero, `<dest>` should be well-defined, otherwise the behavior is undefined.

The behavior of ‘`llvm.memset.inline.*`’ is equivalent to the behavior of ‘`llvm.memset.*`’, but the generated code is guaranteed not to call any external functions.

<a id="llvm-experimental-memset-pattern-intrinsic"></a>

<a id="int-experimental-memset-pattern"></a>

#### ‘`llvm.experimental.memset.pattern`’ Intrinsic

<a id="id558"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.experimental.memset.pattern` on any sized type and for different address spaces.

    declare void @llvm.experimental.memset.pattern.p0.i128.i64(ptr <dest>, i128 <val>,
                                                               i64 <count>, i1 <isvolatile>)

<a id="id559"></a>

##### Overview:

The ‘`llvm.experimental.memset.pattern.*`’ intrinsics fill a block of memory with a particular value. This may be expanded to an inline loop, a sequence of stores, or a libcall depending on what is available for the target and the expected performance and code size impact.

<a id="id560"></a>

##### Arguments:

The first argument is a pointer to the destination to fill, the second is the value with which to fill it, the third argument is an integer argument specifying the number of times to fill the value, and the fourth is a boolean indicating a volatile access.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first argument.

If the `isvolatile` parameter is `true`, the `llvm.experimental.memset.pattern` call is a [volatile operation](high-level-structure.md#volatile). The detailed access behavior is not very cleanly specified and it is unwise to depend on it.

<a id="id561"></a>

##### Semantics:

The ‘`llvm.experimental.memset.pattern*`’ intrinsic fills memory starting at the destination location with the given pattern `<count>` times, incrementing by the allocation size of the type each time. The stores follow the usual semantics of store instructions, including regarding endianness and padding. If the argument is known to be aligned to some boundary, this can be specified as an attribute on the argument.

If `<count>` is 0, it is no-op modulo the behavior of attributes attached to the arguments. If `<count>` is not a well-defined value, the behavior is undefined. If `<count>` is not zero, `<dest>` should be well-defined, otherwise the behavior is undefined.

<a id="llvm-sqrt-intrinsic"></a>

<a id="int-sqrt"></a>

#### ‘`llvm.sqrt.*`’ Intrinsic

<a id="id562"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.sqrt` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.sqrt.f32(float %Val)
    declare double    @llvm.sqrt.f64(double %Val)
    declare x86_fp80  @llvm.sqrt.f80(x86_fp80 %Val)
    declare fp128     @llvm.sqrt.f128(fp128 %Val)
    declare ppc_fp128 @llvm.sqrt.ppcf128(ppc_fp128 %Val)

<a id="id563"></a>

##### Overview:

The ‘`llvm.sqrt`’ intrinsics return the square root of the specified value.

<a id="id564"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id565"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`sqrt`’ function but without trapping or setting `errno`. For types specified by IEEE 754, the result matches a conforming libm implementation.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-powi-intrinsic"></a>

#### ‘`llvm.powi.*`’ Intrinsic

<a id="id566"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.powi` on any floating-point or vector of floating-point type. Not all targets support all types however.

Generally, the only supported type for the exponent is the one matching with the C type `int`.

    declare float     @llvm.powi.f32.i32(float  %Val, i32 %power)
    declare double    @llvm.powi.f64.i16(double %Val, i16 %power)
    declare x86_fp80  @llvm.powi.f80.i32(x86_fp80  %Val, i32 %power)
    declare fp128     @llvm.powi.f128.i32(fp128 %Val, i32 %power)
    declare ppc_fp128 @llvm.powi.ppcf128.i32(ppc_fp128  %Val, i32 %power)

<a id="id567"></a>

##### Overview:

The ‘`llvm.powi.*`’ intrinsics return the first operand raised to the specified (positive or negative) power. The order of evaluation of multiplications is not defined. When a vector of floating-point type is used, the second argument remains a scalar integer value.

<a id="id568"></a>

##### Arguments:

The second argument is an integer power, and the first is a value to raise to that power.

<a id="id569"></a>

##### Semantics:

This function returns the first value raised to the second power with an unspecified sequence of rounding operations.

Note that the `powi` function is unusual in that NaN inputs can lead to non-NaN results, and this depends on the kind of NaN (quiet vs signaling). Due to how [LLVM treats NaN values](high-level-structure.md#floatnan) in non-constrained functions, the function may non-deterministically treat signaling NaNs as quiet NaNs. For example, `powi(QNaN, 0)` returns `1.0`, and `powi(SNaN, 0)` may non-deterministically return `1.0` or a NaN.

<a id="llvm-sin-intrinsic"></a>

<a id="t-llvm-sin"></a>

#### ‘`llvm.sin.*`’ Intrinsic

<a id="id570"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.sin` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.sin.f32(float  %Val)
    declare double    @llvm.sin.f64(double %Val)
    declare x86_fp80  @llvm.sin.f80(x86_fp80  %Val)
    declare fp128     @llvm.sin.f128(fp128 %Val)
    declare ppc_fp128 @llvm.sin.ppcf128(ppc_fp128  %Val)

<a id="id571"></a>

##### Overview:

The ‘`llvm.sin.*`’ intrinsics return the sine of the operand.

<a id="id572"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id573"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`sin`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-cos-intrinsic"></a>

<a id="t-llvm-cos"></a>

#### ‘`llvm.cos.*`’ Intrinsic

<a id="id574"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.cos` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.cos.f32(float  %Val)
    declare double    @llvm.cos.f64(double %Val)
    declare x86_fp80  @llvm.cos.f80(x86_fp80  %Val)
    declare fp128     @llvm.cos.f128(fp128 %Val)
    declare ppc_fp128 @llvm.cos.ppcf128(ppc_fp128  %Val)

<a id="id575"></a>

##### Overview:

The ‘`llvm.cos.*`’ intrinsics return the cosine of the operand.

<a id="id576"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id577"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`cos`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-tan-intrinsic"></a>

#### ‘`llvm.tan.*`’ Intrinsic

<a id="id578"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.tan` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.tan.f32(float  %Val)
    declare double    @llvm.tan.f64(double %Val)
    declare x86_fp80  @llvm.tan.f80(x86_fp80  %Val)
    declare fp128     @llvm.tan.f128(fp128 %Val)
    declare ppc_fp128 @llvm.tan.ppcf128(ppc_fp128  %Val)

<a id="id579"></a>

##### Overview:

The ‘`llvm.tan.*`’ intrinsics return the tangent of the operand.

<a id="id580"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id581"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`tan`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-asin-intrinsic"></a>

#### ‘`llvm.asin.*`’ Intrinsic

<a id="id582"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.asin` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.asin.f32(float  %Val)
    declare double    @llvm.asin.f64(double %Val)
    declare x86_fp80  @llvm.asin.f80(x86_fp80  %Val)
    declare fp128     @llvm.asin.f128(fp128 %Val)
    declare ppc_fp128 @llvm.asin.ppcf128(ppc_fp128  %Val)

<a id="id583"></a>

##### Overview:

The ‘`llvm.asin.*`’ intrinsics return the arcsine of the operand.

<a id="id584"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id585"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`asin`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-acos-intrinsic"></a>

#### ‘`llvm.acos.*`’ Intrinsic

<a id="id586"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.acos` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.acos.f32(float  %Val)
    declare double    @llvm.acos.f64(double %Val)
    declare x86_fp80  @llvm.acos.f80(x86_fp80  %Val)
    declare fp128     @llvm.acos.f128(fp128 %Val)
    declare ppc_fp128 @llvm.acos.ppcf128(ppc_fp128  %Val)

<a id="id587"></a>

##### Overview:

The ‘`llvm.acos.*`’ intrinsics return the arccosine of the operand.

<a id="id588"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id589"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`acos`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-atan-intrinsic"></a>

#### ‘`llvm.atan.*`’ Intrinsic

<a id="id590"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.atan` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.atan.f32(float  %Val)
    declare double    @llvm.atan.f64(double %Val)
    declare x86_fp80  @llvm.atan.f80(x86_fp80  %Val)
    declare fp128     @llvm.atan.f128(fp128 %Val)
    declare ppc_fp128 @llvm.atan.ppcf128(ppc_fp128  %Val)

<a id="id591"></a>

##### Overview:

The ‘`llvm.atan.*`’ intrinsics return the arctangent of the operand.

<a id="id592"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id593"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`atan`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-atan2-intrinsic"></a>

#### ‘`llvm.atan2.*`’ Intrinsic

<a id="id594"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.atan2` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.atan2.f32(float  %Y, float %X)
    declare double    @llvm.atan2.f64(double %Y, double %X)
    declare x86_fp80  @llvm.atan2.f80(x86_fp80  %Y, x86_fp80 %X)
    declare fp128     @llvm.atan2.f128(fp128 %Y, fp128 %X)
    declare ppc_fp128 @llvm.atan2.ppcf128(ppc_fp128  %Y, ppc_fp128 %X)

<a id="id595"></a>

##### Overview:

The ‘`llvm.atan2.*`’ intrinsics return the arctangent of `Y/X` accounting for the quadrant.

<a id="id596"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id597"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`atan2`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-sinh-intrinsic"></a>

#### ‘`llvm.sinh.*`’ Intrinsic

<a id="id598"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.sinh` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.sinh.f32(float  %Val)
    declare double    @llvm.sinh.f64(double %Val)
    declare x86_fp80  @llvm.sinh.f80(x86_fp80  %Val)
    declare fp128     @llvm.sinh.f128(fp128 %Val)
    declare ppc_fp128 @llvm.sinh.ppcf128(ppc_fp128  %Val)

<a id="id599"></a>

##### Overview:

The ‘`llvm.sinh.*`’ intrinsics return the hyperbolic sine of the operand.

<a id="id600"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id601"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`sinh`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-cosh-intrinsic"></a>

#### ‘`llvm.cosh.*`’ Intrinsic

<a id="id602"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.cosh` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.cosh.f32(float  %Val)
    declare double    @llvm.cosh.f64(double %Val)
    declare x86_fp80  @llvm.cosh.f80(x86_fp80  %Val)
    declare fp128     @llvm.cosh.f128(fp128 %Val)
    declare ppc_fp128 @llvm.cosh.ppcf128(ppc_fp128  %Val)

<a id="id603"></a>

##### Overview:

The ‘`llvm.cosh.*`’ intrinsics return the hyperbolic cosine of the operand.

<a id="id604"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id605"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`cosh`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-tanh-intrinsic"></a>

#### ‘`llvm.tanh.*`’ Intrinsic

<a id="id606"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.tanh` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.tanh.f32(float  %Val)
    declare double    @llvm.tanh.f64(double %Val)
    declare x86_fp80  @llvm.tanh.f80(x86_fp80  %Val)
    declare fp128     @llvm.tanh.f128(fp128 %Val)
    declare ppc_fp128 @llvm.tanh.ppcf128(ppc_fp128  %Val)

<a id="id607"></a>

##### Overview:

The ‘`llvm.tanh.*`’ intrinsics return the hyperbolic tangent of the operand.

<a id="id608"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id609"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`tanh`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-sincos-intrinsic"></a>

#### ‘`llvm.sincos.*`’ Intrinsic

<a id="id610"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.sincos` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare { float, float }          @llvm.sincos.f32(float  %Val)
    declare { double, double }        @llvm.sincos.f64(double %Val)
    declare { x86_fp80, x86_fp80 }    @llvm.sincos.f80(x86_fp80  %Val)
    declare { fp128, fp128 }          @llvm.sincos.f128(fp128 %Val)
    declare { ppc_fp128, ppc_fp128 }  @llvm.sincos.ppcf128(ppc_fp128  %Val)
    declare { <4 x float>, <4 x float> } @llvm.sincos.v4f32(<4 x float>  %Val)

<a id="id611"></a>

##### Overview:

The ‘`llvm.sincos.*`’ intrinsics returns the sine and cosine of the operand.

<a id="id612"></a>

##### Arguments:

The argument is a [floating-point](type-system.md#t-floating) value or [vector](type-system.md#t-vector) of floating-point values. Returns two values matching the argument type in a struct.

<a id="id613"></a>

##### Semantics:

This intrinsic is equivalent to a calling both [llvm.sin](#t-llvm-sin) and [llvm.cos](#t-llvm-cos) on the argument.

The first result is the sine of the argument and the second result is the cosine of the argument.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-sincospi-intrinsic"></a>

#### ‘`llvm.sincospi.*`’ Intrinsic

<a id="id614"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.sincospi` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare { float, float }          @llvm.sincospi.f32(float  %Val)
    declare { double, double }        @llvm.sincospi.f64(double %Val)
    declare { x86_fp80, x86_fp80 }    @llvm.sincospi.f80(x86_fp80  %Val)
    declare { fp128, fp128 }          @llvm.sincospi.f128(fp128 %Val)
    declare { ppc_fp128, ppc_fp128 }  @llvm.sincospi.ppcf128(ppc_fp128  %Val)
    declare { <4 x float>, <4 x float> } @llvm.sincospi.v4f32(<4 x float>  %Val)

<a id="id615"></a>

##### Overview:

The ‘`llvm.sincospi.*`’ intrinsics returns the sine and cosine of pi\*operand.

<a id="id616"></a>

##### Arguments:

The argument is a [floating-point](type-system.md#t-floating) value or [vector](type-system.md#t-vector) of floating-point values. Returns two values matching the argument type in a struct.

<a id="id617"></a>

##### Semantics:

This is equivalent to the `llvm.sincos.*` intrinsic where the argument has been multiplied by pi, however, it computes the result more accurately especially for large input values.

Note

Currently, the default lowering of this intrinsic relies on the `sincospi[f|l]` functions being available in the target’s runtime (e.g., libc).

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-modf-intrinsic"></a>

#### ‘`llvm.modf.*`’ Intrinsic

<a id="id618"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.modf` on any floating-point or vector of floating-point type. However, not all targets support all types.

    declare { float, float }             @llvm.modf.f32(float  %Val)
    declare { double, double }           @llvm.modf.f64(double %Val)
    declare { x86_fp80, x86_fp80 }       @llvm.modf.f80(x86_fp80  %Val)
    declare { fp128, fp128 }             @llvm.modf.f128(fp128 %Val)
    declare { ppc_fp128, ppc_fp128 }     @llvm.modf.ppcf128(ppc_fp128  %Val)
    declare { <4 x float>, <4 x float> } @llvm.modf.v4f32(<4 x float>  %Val)

<a id="id619"></a>

##### Overview:

The ‘`llvm.modf.*`’ intrinsics return the operand’s integral and fractional parts.

<a id="id620"></a>

##### Arguments:

The argument is a [floating-point](type-system.md#t-floating) value or [vector](type-system.md#t-vector) of floating-point values. Returns two values matching the argument type in a struct.

<a id="id621"></a>

##### Semantics:

Return the same values as a corresponding libm ‘`modf`’ function without trapping or setting `errno`.

The first result is the fractional part of the operand and the second result is the integral part of the operand. Both results have the same sign as the operand.

Not including exceptional inputs (listed below), `llvm.modf.*` is semantically equivalent to:

    %fp = frem <fptype> %x, 1.0  ; Fractional part
    %ip = fsub <fptype> %x, %fp  ; Integral part

(assuming no floating-point precision errors)

If the argument is a zero, returns a zero with the same sign for both the fractional and integral parts.

If the argument is an infinity, returns a fractional part of zero with the same sign, and infinity with the same sign as the integral part.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-pow-intrinsic"></a>

#### ‘`llvm.pow.*`’ Intrinsic

<a id="id622"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.pow` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.pow.f32(float  %Val, float %Power)
    declare double    @llvm.pow.f64(double %Val, double %Power)
    declare x86_fp80  @llvm.pow.f80(x86_fp80  %Val, x86_fp80 %Power)
    declare fp128     @llvm.pow.f128(fp128 %Val, fp128 %Power)
    declare ppc_fp128 @llvm.pow.ppcf128(ppc_fp128  %Val, ppc_fp128 Power)

<a id="id623"></a>

##### Overview:

The ‘`llvm.pow.*`’ intrinsics return the first operand raised to the specified (positive or negative) power.

<a id="id624"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id625"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`pow`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

Note that the `pow` function is unusual in that NaN inputs can lead to non-NaN results, and this depends on the kind of NaN (quiet vs signaling). Due to how [LLVM treats NaN values](high-level-structure.md#floatnan) in non-constrained functions, the function may non-deterministically treat signaling NaNs as quiet NaNs. For example, `pow(QNaN, 0.0)` returns `1.0`, and `pow(SNaN, 0.0)` may non-deterministically return `1.0` or a NaN.

<a id="llvm-exp-intrinsic"></a>

<a id="int-exp"></a>

#### ‘`llvm.exp.*`’ Intrinsic

<a id="id626"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.exp` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.exp.f32(float  %Val)
    declare double    @llvm.exp.f64(double %Val)
    declare x86_fp80  @llvm.exp.f80(x86_fp80  %Val)
    declare fp128     @llvm.exp.f128(fp128 %Val)
    declare ppc_fp128 @llvm.exp.ppcf128(ppc_fp128  %Val)

<a id="id627"></a>

##### Overview:

The ‘`llvm.exp.*`’ intrinsics compute the base-e exponential of the specified value.

<a id="id628"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id629"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`exp`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-exp2-intrinsic"></a>

<a id="int-exp2"></a>

#### ‘`llvm.exp2.*`’ Intrinsic

<a id="id630"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.exp2` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.exp2.f32(float  %Val)
    declare double    @llvm.exp2.f64(double %Val)
    declare x86_fp80  @llvm.exp2.f80(x86_fp80  %Val)
    declare fp128     @llvm.exp2.f128(fp128 %Val)
    declare ppc_fp128 @llvm.exp2.ppcf128(ppc_fp128  %Val)

<a id="id631"></a>

##### Overview:

The ‘`llvm.exp2.*`’ intrinsics compute the base-2 exponential of the specified value.

<a id="id632"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id633"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`exp2`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-exp10-intrinsic"></a>

<a id="int-exp10"></a>

#### ‘`llvm.exp10.*`’ Intrinsic

<a id="id634"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.exp10` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.exp10.f32(float  %Val)
    declare double    @llvm.exp10.f64(double %Val)
    declare x86_fp80  @llvm.exp10.f80(x86_fp80  %Val)
    declare fp128     @llvm.exp10.f128(fp128 %Val)
    declare ppc_fp128 @llvm.exp10.ppcf128(ppc_fp128  %Val)

<a id="id635"></a>

##### Overview:

The ‘`llvm.exp10.*`’ intrinsics compute the base-10 exponential of the specified value.

<a id="id636"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id637"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`exp10`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-ldexp-intrinsic"></a>

#### ‘`llvm.ldexp.*`’ Intrinsic

<a id="id638"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.ldexp` on any floating point or vector of floating point type. Not all targets support all types however.

    declare float     @llvm.ldexp.f32.i32(float %Val, i32 %Exp)
    declare double    @llvm.ldexp.f64.i32(double %Val, i32 %Exp)
    declare x86_fp80  @llvm.ldexp.f80.i32(x86_fp80 %Val, i32 %Exp)
    declare fp128     @llvm.ldexp.f128.i32(fp128 %Val, i32 %Exp)
    declare ppc_fp128 @llvm.ldexp.ppcf128.i32(ppc_fp128 %Val, i32 %Exp)
    declare <2 x float> @llvm.ldexp.v2f32.v2i32(<2 x float> %Val, <2 x i32> %Exp)

<a id="id639"></a>

##### Overview:

The ‘`llvm.ldexp.*`’ intrinsics perform the ldexp function.

<a id="id640"></a>

##### Arguments:

The first argument and the return value are [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values of the same type. The second argument is an integer with the same number of elements.

<a id="id641"></a>

##### Semantics:

This function multiplies the first argument by 2 raised to the second argument’s power. If the first argument is NaN or infinite, the same value is returned. If the result underflows a zero with the same sign is returned. If the result overflows, the result is an infinity with the same sign.

<a id="llvm-frexp-intrinsic"></a>

<a id="int-frexp"></a>

#### ‘`llvm.frexp.*`’ Intrinsic

<a id="id642"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.frexp` on any floating point or vector of floating point type. Not all targets support all types however.

    declare { float, i32 }     @llvm.frexp.f32.i32(float %Val)
    declare { double, i32 }    @llvm.frexp.f64.i32(double %Val)
    declare { x86_fp80, i32 }  @llvm.frexp.f80.i32(x86_fp80 %Val)
    declare { fp128, i32 }     @llvm.frexp.f128.i32(fp128 %Val)
    declare { ppc_fp128, i32 } @llvm.frexp.ppcf128.i32(ppc_fp128 %Val)
    declare { <2 x float>, <2 x i32> }  @llvm.frexp.v2f32.v2i32(<2 x float> %Val)

<a id="id643"></a>

##### Overview:

The ‘`llvm.frexp.*`’ intrinsics perform the frexp function.

<a id="id644"></a>

##### Arguments:

The argument is a [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Returns two values in a struct. The first struct field matches the argument type, and the second field is an integer or a vector of integer values with the same number of elements as the argument.

<a id="id645"></a>

##### Semantics:

This intrinsic splits a floating point value into a normalized fractional component and integral exponent.

For a non-zero argument, returns the argument multiplied by some power of two such that the absolute value of the returned value is in the range \[0.5, 1.0), with the same sign as the argument. The second result is an integer such that the first result raised to the power of the second result is the input argument.

If the argument is a zero, returns a zero with the same sign and a 0 exponent.

If the argument is a NaN, a NaN is returned and the returned exponent is unspecified.

If the argument is an infinity, returns an infinity with the same sign and an unspecified exponent.

<a id="llvm-log-intrinsic"></a>

<a id="int-log"></a>

#### ‘`llvm.log.*`’ Intrinsic

<a id="id646"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.log` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.log.f32(float  %Val)
    declare double    @llvm.log.f64(double %Val)
    declare x86_fp80  @llvm.log.f80(x86_fp80  %Val)
    declare fp128     @llvm.log.f128(fp128 %Val)
    declare ppc_fp128 @llvm.log.ppcf128(ppc_fp128  %Val)

<a id="id647"></a>

##### Overview:

The ‘`llvm.log.*`’ intrinsics compute the base-e logarithm of the specified value.

<a id="id648"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id649"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`log`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-log10-intrinsic"></a>

<a id="int-log10"></a>

#### ‘`llvm.log10.*`’ Intrinsic

<a id="id650"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.log10` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.log10.f32(float  %Val)
    declare double    @llvm.log10.f64(double %Val)
    declare x86_fp80  @llvm.log10.f80(x86_fp80  %Val)
    declare fp128     @llvm.log10.f128(fp128 %Val)
    declare ppc_fp128 @llvm.log10.ppcf128(ppc_fp128  %Val)

<a id="id651"></a>

##### Overview:

The ‘`llvm.log10.*`’ intrinsics compute the base-10 logarithm of the specified value.

<a id="id652"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id653"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`log10`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-log2-intrinsic"></a>

<a id="int-log2"></a>

#### ‘`llvm.log2.*`’ Intrinsic

<a id="id654"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.log2` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.log2.f32(float  %Val)
    declare double    @llvm.log2.f64(double %Val)
    declare x86_fp80  @llvm.log2.f80(x86_fp80  %Val)
    declare fp128     @llvm.log2.f128(fp128 %Val)
    declare ppc_fp128 @llvm.log2.ppcf128(ppc_fp128  %Val)

<a id="id655"></a>

##### Overview:

The ‘`llvm.log2.*`’ intrinsics compute the base-2 logarithm of the specified value.

<a id="id656"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id657"></a>

##### Semantics:

Return the same value as a corresponding libm ‘`log2`’ function but without trapping or setting `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-fma-intrinsic"></a>

<a id="int-fma"></a>

#### ‘`llvm.fma.*`’ Intrinsic

<a id="id658"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.fma` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.fma.f32(float  %a, float  %b, float  %c)
    declare double    @llvm.fma.f64(double %a, double %b, double %c)
    declare x86_fp80  @llvm.fma.f80(x86_fp80 %a, x86_fp80 %b, x86_fp80 %c)
    declare fp128     @llvm.fma.f128(fp128 %a, fp128 %b, fp128 %c)
    declare ppc_fp128 @llvm.fma.ppcf128(ppc_fp128 %a, ppc_fp128 %b, ppc_fp128 %c)

<a id="id659"></a>

##### Overview:

The ‘`llvm.fma.*`’ intrinsics perform the fused multiply-add operation.

<a id="id660"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id661"></a>

##### Semantics:

Return the same value as the IEEE 754 fusedMultiplyAdd operation. This is assumed to not trap or set `errno`.

When specified with the fast-math-flag ‘afn’, the result may be approximated using a less accurate calculation.

<a id="llvm-fabs-intrinsic"></a>

<a id="int-fabs"></a>

#### ‘`llvm.fabs.*`’ Intrinsic

<a id="id662"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.fabs` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.fabs.f32(float  %Val)
    declare double    @llvm.fabs.f64(double %Val)
    declare x86_fp80  @llvm.fabs.f80(x86_fp80 %Val)
    declare fp128     @llvm.fabs.f128(fp128 %Val)
    declare ppc_fp128 @llvm.fabs.ppcf128(ppc_fp128 %Val)

<a id="id663"></a>

##### Overview:

The ‘`llvm.fabs.*`’ intrinsics return the absolute value of the operand.

<a id="id664"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id665"></a>

##### Semantics:

This function returns the same values as the libm `fabs` functions would, and handles error conditions in the same way. The returned value is completely identical to the input except for the sign bit; in particular, if the input is a NaN, then the quiet/signaling bit and payload are perfectly preserved.

<a id="floating-point-min-max-intrinsics-comparison"></a>

<a id="i-fminmax-family"></a>

#### Floating-point min/max intrinsics comparison

LLVM supports three pairs of floating-point min/max intrinsics, which differ in their handling of [NaN values](high-level-structure.md#floatnan):

- `llvm.minimum` and `llvm.maximum`: Return NaN if one the arguments is NaN.

- `llvm.minimumnum` and `llvm.maximumnum`: Return the other argument if one of the arguments is NaN.

- `llvm.minnum` and `llvm.maxnum`: For quiet NaNs behaves like minimumnum/maximumnum. For signaling NaNs, non-deterministically returns NaN or the other operand.

Additionally, each of these intrinsics supports two behaviors for signed zeros. By default, -0.0 is considered smaller than +0.0. If the `nsz` flag is specified, the order is non-deterministic: If the two inputs are zeros with opposite sign, either input may be returned.

The mapping between the LLVM intrinsics, C functions and IEEE 754 functions is as follows (up to divergences permitted by the usual `NaN rules <floatnan>`):

| LLVM intrinsic    | llvm.minnum with nsz flag | llvm.minimum   | llvm.minimumnum      |
|-------------------|---------------------------|----------------|----------------------|
| C function        | fmin                      | fminimum       | fminimum_num         |
| IEEE 754 function | minNum (2008)             | minimum (2019) | minimumNumber (2019) |

<a id="llvm-minnum-intrinsic"></a>

<a id="i-minnum"></a>

#### ‘`llvm.minnum.*`’ Intrinsic

<a id="id666"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.minnum` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.minnum.f32(float %Val0, float %Val1)
    declare double    @llvm.minnum.f64(double %Val0, double %Val1)
    declare x86_fp80  @llvm.minnum.f80(x86_fp80 %Val0, x86_fp80 %Val1)
    declare fp128     @llvm.minnum.f128(fp128 %Val0, fp128 %Val1)
    declare ppc_fp128 @llvm.minnum.ppcf128(ppc_fp128 %Val0, ppc_fp128 %Val1)

<a id="id667"></a>

##### Overview:

The ‘`llvm.minnum.*`’ intrinsics return the minimum of the two arguments.

<a id="id668"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id669"></a>

##### Semantics:

If both operands are qNaNs, returns a [NaN](high-level-structure.md#floatnan). If one operand is qNaN and another operand is a number, returns the number. If both operands are numbers, returns the lesser of the two arguments. -0.0 is considered to be less than +0.0 for this intrinsic.

If an operand is a signaling NaN, then the intrinsic will non-deterministically either:

- Return a [NaN](high-level-structure.md#floatnan).

- Or treat the signaling NaN as a quiet NaN.

If the `nsz` flag is specified, `llvm.minnum` with one +0.0 and one -0.0 operand may non-deterministically return either operand. Contrary to normal `nsz` semantics, if both operands have the same sign, the result must also have the same sign.

When used with the `nsz` flag, this intrinsic follows the semantics of `fmin` in C and `minNum` in IEEE 754-2008, except for signaling NaN inputs, which follow [LLVM’s usual signaling NaN behavior](high-level-structure.md#floatnan) instead.

The `llvm.minnum` intrinsic can be refined into `llvm.minimumnum`, as the latter exhibits a subset of behaviors of the former.

Warning

If the intrinsic is used without nsz, not all backends currently respect the specified signed zero ordering. Do not rely on it until this warning has been removed. See [issue #174730](https://github.com/llvm/llvm-project/issues/174730).

<a id="llvm-maxnum-intrinsic"></a>

<a id="i-maxnum"></a>

#### ‘`llvm.maxnum.*`’ Intrinsic

<a id="id670"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.maxnum` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.maxnum.f32(float  %Val0, float  %Val1)
    declare double    @llvm.maxnum.f64(double %Val0, double %Val1)
    declare x86_fp80  @llvm.maxnum.f80(x86_fp80  %Val0, x86_fp80  %Val1)
    declare fp128     @llvm.maxnum.f128(fp128 %Val0, fp128 %Val1)
    declare ppc_fp128 @llvm.maxnum.ppcf128(ppc_fp128  %Val0, ppc_fp128  %Val1)

<a id="id671"></a>

##### Overview:

The ‘`llvm.maxnum.*`’ intrinsics return the maximum of the two arguments.

<a id="id672"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id673"></a>

##### Semantics:

If both operands are qNaNs, returns a [NaN](high-level-structure.md#floatnan). If one operand is qNaN and another operand is a number, returns the number. If both operands are numbers, returns the greater of the two arguments. -0.0 is considered to be less than +0.0 for this intrinsic.

If an operand is a signaling NaN, then the intrinsic will non-deterministically either:

- Return a [NaN](high-level-structure.md#floatnan).

- Or treat the signaling NaN as a quiet NaN.

If the `nsz` flag is specified, `llvm.maxnum` with one +0.0 and one -0.0 operand may non-deterministically return either operand. Contrary to normal `nsz` semantics, if both operands have the same sign, the result must also have the same sign.

When used with the `nsz` flag, this intrinsic follows the semantics of `fmax` in C and `maxNum` in IEEE 754-2008, except for signaling NaN inputs, which follow [LLVM’s usual signaling NaN behavior](high-level-structure.md#floatnan) instead.

The `llvm.maxnum` intrinsic can be refined into `llvm.maximumnum`, as the latter exhibits a subset of behaviors of the former.

Warning

If the intrinsic is used without nsz, not all backends currently respect the specified signed zero ordering. Do not rely on it until this warning has been removed. See [issue #174730](https://github.com/llvm/llvm-project/issues/174730).

<a id="llvm-minimum-intrinsic"></a>

<a id="i-minimum"></a>

#### ‘`llvm.minimum.*`’ Intrinsic

<a id="id674"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.minimum` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.minimum.f32(float %Val0, float %Val1)
    declare double    @llvm.minimum.f64(double %Val0, double %Val1)
    declare x86_fp80  @llvm.minimum.f80(x86_fp80 %Val0, x86_fp80 %Val1)
    declare fp128     @llvm.minimum.f128(fp128 %Val0, fp128 %Val1)
    declare ppc_fp128 @llvm.minimum.ppcf128(ppc_fp128 %Val0, ppc_fp128 %Val1)

<a id="id675"></a>

##### Overview:

The ‘`llvm.minimum.*`’ intrinsics return the minimum of the two arguments, propagating NaNs and treating -0.0 as less than +0.0.

<a id="id676"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id677"></a>

##### Semantics:

If either operand is a NaN, returns a [NaN](high-level-structure.md#floatnan). Otherwise returns the lesser of the two arguments. -0.0 is considered to be less than +0.0 for this intrinsic.

This intrinsic follows the semantics of `fminimum` in C23 and `minimum` in IEEE 754-2019, except for signaling NaN inputs, which follow [LLVM’s usual signaling NaN behavior](high-level-structure.md#floatnan) instead.

If the `nsz` flag is specified, `llvm.maximum` with one +0.0 and one -0.0 operand may non-deterministically return either operand. Contrary to normal `nsz` semantics, if both operands have the same sign, the result must also have the same sign.

<a id="llvm-maximum-intrinsic"></a>

<a id="i-maximum"></a>

#### ‘`llvm.maximum.*`’ Intrinsic

<a id="id678"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.maximum` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.maximum.f32(float %Val0, float %Val1)
    declare double    @llvm.maximum.f64(double %Val0, double %Val1)
    declare x86_fp80  @llvm.maximum.f80(x86_fp80 %Val0, x86_fp80 %Val1)
    declare fp128     @llvm.maximum.f128(fp128 %Val0, fp128 %Val1)
    declare ppc_fp128 @llvm.maximum.ppcf128(ppc_fp128 %Val0, ppc_fp128 %Val1)

<a id="id679"></a>

##### Overview:

The ‘`llvm.maximum.*`’ intrinsics return the maximum of the two arguments, propagating NaNs and treating -0.0 as less than +0.0.

<a id="id680"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id681"></a>

##### Semantics:

If either operand is a NaN, returns a [NaN](high-level-structure.md#floatnan). Otherwise returns the greater of the two arguments. -0.0 is considered to be less than +0.0 for this intrinsic.

This intrinsic follows the semantics of `fmaximum` in C23 and `maximum` in IEEE 754-2019, except for signaling NaN inputs, which follow [LLVM’s usual signaling NaN behavior](high-level-structure.md#floatnan) instead.

If the `nsz` flag is specified, `llvm.maximum` with one +0.0 and one -0.0 operand may non-deterministically return either operand. Contrary to normal `nsz` semantics, if both operands have the same sign, the result must also have the same sign.

<a id="llvm-minimumnum-intrinsic"></a>

<a id="i-minimumnum"></a>

#### ‘`llvm.minimumnum.*`’ Intrinsic

<a id="id682"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.minimumnum` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.minimumnum.f32(float %Val0, float %Val1)
    declare double    @llvm.minimumnum.f64(double %Val0, double %Val1)
    declare x86_fp80  @llvm.minimumnum.f80(x86_fp80 %Val0, x86_fp80 %Val1)
    declare fp128     @llvm.minimumnum.f128(fp128 %Val0, fp128 %Val1)
    declare ppc_fp128 @llvm.minimumnum.ppcf128(ppc_fp128 %Val0, ppc_fp128 %Val1)

<a id="id683"></a>

##### Overview:

The ‘`llvm.minimumnum.*`’ intrinsics return the minimum of the two arguments, not propagating NaNs and treating -0.0 as less than +0.0.

<a id="id684"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id685"></a>

##### Semantics:

If both operands are NaNs (including sNaN), returns a [NaN](high-level-structure.md#floatnan). If one operand is NaN (including sNaN) and another operand is a number, return the number. Otherwise returns the lesser of the two arguments. -0.0 is considered to be less than +0.0 for this intrinsic.

If the `nsz` flag is specified, `llvm.minimumnum` with one +0.0 and one -0.0 operand may non-deterministically return either operand. Contrary to normal `nsz` semantics, if both operands have the same sign, the result must also have the same sign.

This intrinsic follows the semantics of `fminimum_num` in C23 and `minimumNumber` in IEEE 754-2019, except for signaling NaN inputs, which follow [LLVM’s usual signaling NaN behavior](high-level-structure.md#floatnan) instead.

This intrinsic behaves the same as `llvm.minnum` other than its treatment of sNaN inputs.

<a id="llvm-maximumnum-intrinsic"></a>

<a id="i-maximumnum"></a>

#### ‘`llvm.maximumnum.*`’ Intrinsic

<a id="id686"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.maximumnum` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.maximumnum.f32(float %Val0, float %Val1)
    declare double    @llvm.maximumnum.f64(double %Val0, double %Val1)
    declare x86_fp80  @llvm.maximumnum.f80(x86_fp80 %Val0, x86_fp80 %Val1)
    declare fp128     @llvm.maximumnum.f128(fp128 %Val0, fp128 %Val1)
    declare ppc_fp128 @llvm.maximumnum.ppcf128(ppc_fp128 %Val0, ppc_fp128 %Val1)

<a id="id687"></a>

##### Overview:

The ‘`llvm.maximumnum.*`’ intrinsics return the maximum of the two arguments, not propagating NaNs and treating -0.0 as less than +0.0.

<a id="id688"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id689"></a>

##### Semantics:

If both operands are NaNs (including sNaN), returns a [NaN](high-level-structure.md#floatnan). If one operand is NaN (including sNaN) and another operand is a number, return the number. Otherwise returns the greater of the two arguments. -0.0 is considered to be less than +0.0 for this intrinsic.

If the `nsz` flag is specified, `llvm.maximumnum` with one +0.0 and one -0.0 operand may non-deterministically return either operand. Contrary to normal `nsz` semantics, if both operands have the same sign, the result must also have the same sign.

This intrinsic follows the semantics of `fmaximum_num` in C23 and `maximumNumber` in IEEE 754-2019, except for signaling NaN inputs, which follow [LLVM’s usual signaling NaN behavior](high-level-structure.md#floatnan) instead.

This intrinsic behaves the same as `llvm.maxnum` other than its treatment of sNaN inputs.

<a id="llvm-copysign-intrinsic"></a>

<a id="int-copysign"></a>

#### ‘`llvm.copysign.*`’ Intrinsic

<a id="id690"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.copysign` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.copysign.f32(float  %Mag, float  %Sgn)
    declare double    @llvm.copysign.f64(double %Mag, double %Sgn)
    declare x86_fp80  @llvm.copysign.f80(x86_fp80  %Mag, x86_fp80  %Sgn)
    declare fp128     @llvm.copysign.f128(fp128 %Mag, fp128 %Sgn)
    declare ppc_fp128 @llvm.copysign.ppcf128(ppc_fp128  %Mag, ppc_fp128  %Sgn)

<a id="id691"></a>

##### Overview:

The ‘`llvm.copysign.*`’ intrinsics return a value with the magnitude of the first operand and the sign of the second operand.

<a id="id692"></a>

##### Arguments:

The arguments and return value are floating-point numbers of the same type.

<a id="id693"></a>

##### Semantics:

This function returns the same values as the libm `copysign` functions would, and handles error conditions in the same way. The returned value is completely identical to the first operand except for the sign bit; in particular, if the input is a NaN, then the quiet/signaling bit and payload are perfectly preserved.

<a id="llvm-floor-intrinsic"></a>

<a id="int-floor"></a>

#### ‘`llvm.floor.*`’ Intrinsic

<a id="id694"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.floor` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.floor.f32(float  %Val)
    declare double    @llvm.floor.f64(double %Val)
    declare x86_fp80  @llvm.floor.f80(x86_fp80  %Val)
    declare fp128     @llvm.floor.f128(fp128 %Val)
    declare ppc_fp128 @llvm.floor.ppcf128(ppc_fp128  %Val)

<a id="id695"></a>

##### Overview:

The ‘`llvm.floor.*`’ intrinsics return the floor of the operand.

<a id="id696"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id697"></a>

##### Semantics:

This function returns the same values as the libm `floor` functions would, and handles error conditions in the same way.

<a id="llvm-ceil-intrinsic"></a>

<a id="int-ceil"></a>

#### ‘`llvm.ceil.*`’ Intrinsic

<a id="id698"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.ceil` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.ceil.f32(float  %Val)
    declare double    @llvm.ceil.f64(double %Val)
    declare x86_fp80  @llvm.ceil.f80(x86_fp80  %Val)
    declare fp128     @llvm.ceil.f128(fp128 %Val)
    declare ppc_fp128 @llvm.ceil.ppcf128(ppc_fp128  %Val)

<a id="id699"></a>

##### Overview:

The ‘`llvm.ceil.*`’ intrinsics return the ceiling of the operand.

<a id="id700"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id701"></a>

##### Semantics:

This function returns the same values as the libm `ceil` functions would, and handles error conditions in the same way.

<a id="llvm-trunc-intrinsic"></a>

<a id="int-llvm-trunc"></a>

#### ‘`llvm.trunc.*`’ Intrinsic

<a id="id702"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.trunc` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.trunc.f32(float  %Val)
    declare double    @llvm.trunc.f64(double %Val)
    declare x86_fp80  @llvm.trunc.f80(x86_fp80  %Val)
    declare fp128     @llvm.trunc.f128(fp128 %Val)
    declare ppc_fp128 @llvm.trunc.ppcf128(ppc_fp128  %Val)

<a id="id703"></a>

##### Overview:

The ‘`llvm.trunc.*`’ intrinsics returns the operand rounded to the nearest integer not larger in magnitude than the operand.

<a id="id704"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id705"></a>

##### Semantics:

This function returns the same values as the libm `trunc` functions would, and handles error conditions in the same way.

<a id="llvm-rint-intrinsic"></a>

<a id="int-rint"></a>

#### ‘`llvm.rint.*`’ Intrinsic

<a id="id706"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.rint` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.rint.f32(float  %Val)
    declare double    @llvm.rint.f64(double %Val)
    declare x86_fp80  @llvm.rint.f80(x86_fp80  %Val)
    declare fp128     @llvm.rint.f128(fp128 %Val)
    declare ppc_fp128 @llvm.rint.ppcf128(ppc_fp128  %Val)

<a id="id707"></a>

##### Overview:

The ‘`llvm.rint.*`’ intrinsics returns the operand rounded to the nearest integer. It may raise an inexact floating-point exception if the operand isn’t an integer.

<a id="id708"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id709"></a>

##### Semantics:

This function returns the same values as the libm `rint` functions would, and handles error conditions in the same way. Since LLVM assumes the [default floating-point environment](high-level-structure.md#floatenv), the rounding mode is assumed to be set to “nearest”, so halfway cases are rounded to the even integer. Use [Constrained Floating-Point Intrinsics](intrinsics-floating-point.md#constrainedfp) to avoid that assumption.

<a id="llvm-nearbyint-intrinsic"></a>

<a id="int-nearbyint"></a>

#### ‘`llvm.nearbyint.*`’ Intrinsic

<a id="id710"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.nearbyint` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.nearbyint.f32(float  %Val)
    declare double    @llvm.nearbyint.f64(double %Val)
    declare x86_fp80  @llvm.nearbyint.f80(x86_fp80  %Val)
    declare fp128     @llvm.nearbyint.f128(fp128 %Val)
    declare ppc_fp128 @llvm.nearbyint.ppcf128(ppc_fp128  %Val)

<a id="id711"></a>

##### Overview:

The ‘`llvm.nearbyint.*`’ intrinsics returns the operand rounded to the nearest integer.

<a id="id712"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id713"></a>

##### Semantics:

This function returns the same values as the libm `nearbyint` functions would, and handles error conditions in the same way. Since LLVM assumes the [default floating-point environment](high-level-structure.md#floatenv), the rounding mode is assumed to be set to “nearest”, so halfway cases are rounded to the even integer. Use [Constrained Floating-Point Intrinsics](intrinsics-floating-point.md#constrainedfp) to avoid that assumption.

<a id="llvm-round-intrinsic"></a>

<a id="int-round"></a>

#### ‘`llvm.round.*`’ Intrinsic

<a id="id714"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.round` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.round.f32(float  %Val)
    declare double    @llvm.round.f64(double %Val)
    declare x86_fp80  @llvm.round.f80(x86_fp80  %Val)
    declare fp128     @llvm.round.f128(fp128 %Val)
    declare ppc_fp128 @llvm.round.ppcf128(ppc_fp128  %Val)

<a id="id715"></a>

##### Overview:

The ‘`llvm.round.*`’ intrinsics returns the operand rounded to the nearest integer.

<a id="id716"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id717"></a>

##### Semantics:

This function returns the same values as the libm `round` functions would, and handles error conditions in the same way.

<a id="llvm-roundeven-intrinsic"></a>

<a id="int-roundeven"></a>

#### ‘`llvm.roundeven.*`’ Intrinsic

<a id="id718"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.roundeven` on any floating-point or vector of floating-point type. Not all targets support all types however.

    declare float     @llvm.roundeven.f32(float  %Val)
    declare double    @llvm.roundeven.f64(double %Val)
    declare x86_fp80  @llvm.roundeven.f80(x86_fp80  %Val)
    declare fp128     @llvm.roundeven.f128(fp128 %Val)
    declare ppc_fp128 @llvm.roundeven.ppcf128(ppc_fp128  %Val)

<a id="id719"></a>

##### Overview:

The ‘`llvm.roundeven.*`’ intrinsics returns the operand rounded to the nearest integer in floating-point format rounding halfway cases to even (that is, to the nearest value that is an even integer).

<a id="id720"></a>

##### Arguments:

The argument and return value are floating-point numbers of the same type.

<a id="id721"></a>

##### Semantics:

This function implements IEEE 754 operation `roundToIntegralTiesToEven`. It also behaves in the same way as C standard function `roundeven`, including that it disregards rounding mode and does not raise floating point exceptions.

<a id="llvm-lround-intrinsic"></a>

#### ‘`llvm.lround.*`’ Intrinsic

<a id="id722"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.lround` on any floating-point type or vector of floating-point type. Not all targets support all types however.

    declare i32 @llvm.lround.i32.f32(float %Val)
    declare i32 @llvm.lround.i32.f64(double %Val)
    declare i32 @llvm.lround.i32.f80(x86_fp80 %Val)
    declare i32 @llvm.lround.i32.f128(fp128 %Val)
    declare i32 @llvm.lround.i32.ppcf128(ppc_fp128 %Val)

    declare i64 @llvm.lround.i64.f32(float %Val)
    declare i64 @llvm.lround.i64.f64(double %Val)
    declare i64 @llvm.lround.i64.f80(x86_fp80 %Val)
    declare i64 @llvm.lround.i64.f128(fp128 %Val)
    declare i64 @llvm.lround.i64.ppcf128(ppc_fp128 %Val)

<a id="id723"></a>

##### Overview:

The ‘`llvm.lround.*`’ intrinsics return the operand rounded to the nearest integer with ties away from zero.

<a id="id724"></a>

##### Arguments:

The argument is a floating-point number and the return value is an integer type.

<a id="id725"></a>

##### Semantics:

This function returns the same values as the libm `lround` functions would, but without setting errno. If the rounded value is too large to be stored in the result type, the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="llvm-llround-intrinsic"></a>

#### ‘`llvm.llround.*`’ Intrinsic

<a id="id726"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.llround` on any floating-point type. Not all targets support all types however.

    declare i64 @llvm.llround.i64.f32(float %Val)
    declare i64 @llvm.llround.i64.f64(double %Val)
    declare i64 @llvm.llround.i64.f80(x86_fp80 %Val)
    declare i64 @llvm.llround.i64.f128(fp128 %Val)
    declare i64 @llvm.llround.i64.ppcf128(ppc_fp128 %Val)

<a id="id727"></a>

##### Overview:

The ‘`llvm.llround.*`’ intrinsics return the operand rounded to the nearest integer with ties away from zero.

<a id="id728"></a>

##### Arguments:

The argument is a floating-point number and the return value is an integer type.

<a id="id729"></a>

##### Semantics:

This function returns the same values as the libm `llround` functions would, but without setting errno. If the rounded value is too large to be stored in the result type, the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="llvm-lrint-intrinsic"></a>

<a id="int-lrint"></a>

#### ‘`llvm.lrint.*`’ Intrinsic

<a id="id730"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.lrint` on any floating-point type or vector of floating-point type. Not all targets support all types however.

    declare i32 @llvm.lrint.i32.f32(float %Val)
    declare i32 @llvm.lrint.i32.f64(double %Val)
    declare i32 @llvm.lrint.i32.f80(x86_fp80 %Val)
    declare i32 @llvm.lrint.i32.f128(fp128 %Val)
    declare i32 @llvm.lrint.i32.ppcf128(ppc_fp128 %Val)

    declare i64 @llvm.lrint.i64.f32(float %Val)
    declare i64 @llvm.lrint.i64.f64(double %Val)
    declare i64 @llvm.lrint.i64.f80(x86_fp80 %Val)
    declare i64 @llvm.lrint.i64.f128(fp128 %Val)
    declare i64 @llvm.lrint.i64.ppcf128(ppc_fp128 %Val)

<a id="id731"></a>

##### Overview:

The ‘`llvm.lrint.*`’ intrinsics return the operand rounded to the nearest integer.

<a id="id732"></a>

##### Arguments:

The argument is a floating-point number and the return value is an integer type.

<a id="id733"></a>

##### Semantics:

This function returns the same values as the libm `lrint` functions would, but without setting errno. If the rounded value is too large to be stored in the result type, the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="llvm-llrint-intrinsic"></a>

<a id="int-llrint"></a>

#### ‘`llvm.llrint.*`’ Intrinsic

<a id="id734"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.llrint` on any floating-point type or vector of floating-point type. Not all targets support all types however.

    declare i64 @llvm.llrint.i64.f32(float %Val)
    declare i64 @llvm.llrint.i64.f64(double %Val)
    declare i64 @llvm.llrint.i64.f80(x86_fp80 %Val)
    declare i64 @llvm.llrint.i64.f128(fp128 %Val)
    declare i64 @llvm.llrint.i64.ppcf128(ppc_fp128 %Val)

<a id="id735"></a>

##### Overview:

The ‘`llvm.llrint.*`’ intrinsics return the operand rounded to the nearest integer.

<a id="id736"></a>

##### Arguments:

The argument is a floating-point number and the return value is an integer type.

<a id="id737"></a>

##### Semantics:

This function returns the same values as the libm `llrint` functions would, but without setting errno. If the rounded value is too large to be stored in the result type, the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="bit-manipulation-intrinsics"></a>

### Bit Manipulation Intrinsics

LLVM provides intrinsics for a few important bit manipulation operations. These allow efficient code generation for some algorithms.

<a id="llvm-bitreverse-intrinsics"></a>

<a id="int-bitreverse"></a>

#### ‘`llvm.bitreverse.*`’ Intrinsics

<a id="id738"></a>

##### Syntax:

This is an overloaded intrinsic function. You can use bitreverse on any integer type.

    declare i16 @llvm.bitreverse.i16(i16 <id>)
    declare i32 @llvm.bitreverse.i32(i32 <id>)
    declare i64 @llvm.bitreverse.i64(i64 <id>)
    declare <4 x i32> @llvm.bitreverse.v4i32(<4 x i32> <id>)

<a id="id739"></a>

##### Overview:

The ‘`llvm.bitreverse`’ family of intrinsics is used to reverse the bitpattern of an integer value or vector of integer values; for example `0b10110110` becomes `0b01101101`.

<a id="id740"></a>

##### Semantics:

The `llvm.bitreverse.iN` intrinsic returns an iN value that has bit `M` in the input moved to bit `N-M-1` in the output. The vector intrinsics, such as `llvm.bitreverse.v4i32`, operate on a per-element basis and the element order is not affected.

<a id="llvm-bswap-intrinsics"></a>

<a id="int-bswap"></a>

#### ‘`llvm.bswap.*`’ Intrinsics

<a id="id741"></a>

##### Syntax:

This is an overloaded intrinsic function. You can use bswap on any integer type that is an even number of bytes (i.e., BitWidth % 16 == 0).

    declare i16 @llvm.bswap.i16(i16 <id>)
    declare i32 @llvm.bswap.i32(i32 <id>)
    declare i64 @llvm.bswap.i64(i64 <id>)
    declare <4 x i32> @llvm.bswap.v4i32(<4 x i32> <id>)

<a id="id742"></a>

##### Overview:

The ‘`llvm.bswap`’ family of intrinsics is used to byte swap an integer value or vector of integer values with an even number of bytes (positive multiple of 16 bits).

<a id="id743"></a>

##### Semantics:

The `llvm.bswap.i16` intrinsic returns an i16 value that has the high and low byte of the input i16 swapped. Similarly, the `llvm.bswap.i32` intrinsic returns an i32 value that has the four bytes of the input i32 swapped, so that if the input bytes are numbered 0, 1, 2, 3 then the returned i32 will have its bytes in 3, 2, 1, 0 order. The `llvm.bswap.i48`, `llvm.bswap.i64` and other intrinsics extend this concept to additional even-byte lengths (6 bytes, 8 bytes and more, respectively). The vector intrinsics, such as `llvm.bswap.v4i32`, operate on a per-element basis and the element order is not affected.

<a id="llvm-ctpop-intrinsic"></a>

<a id="int-ctpop"></a>

#### ‘`llvm.ctpop.*`’ Intrinsic

<a id="id744"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.ctpop` on any integer bit width, or on any vector with integer elements. Not all targets support all bit widths or vector types, however.

    declare i8 @llvm.ctpop.i8(i8  <src>)
    declare i16 @llvm.ctpop.i16(i16 <src>)
    declare i32 @llvm.ctpop.i32(i32 <src>)
    declare i64 @llvm.ctpop.i64(i64 <src>)
    declare i256 @llvm.ctpop.i256(i256 <src>)
    declare <2 x i32> @llvm.ctpop.v2i32(<2 x i32> <src>)

<a id="id745"></a>

##### Overview:

The ‘`llvm.ctpop`’ family of intrinsics counts the number of bits set in a value.

<a id="id746"></a>

##### Arguments:

The only argument is the value to be counted. The argument may be of any integer type, or a vector with integer elements. The return type must match the argument type.

<a id="id747"></a>

##### Semantics:

The ‘`llvm.ctpop`’ intrinsic counts the 1’s in a variable, or within each element of a vector.

<a id="llvm-ctlz-intrinsic"></a>

<a id="int-ctlz"></a>

#### ‘`llvm.ctlz.*`’ Intrinsic

<a id="id748"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.ctlz` on any integer bit width, or any vector whose elements are integers. Not all targets support all bit widths or vector types, however.

    declare i8   @llvm.ctlz.i8  (i8   <src>, i1 <is_zero_poison>)
    declare <2 x i37> @llvm.ctlz.v2i37(<2 x i37> <src>, i1 <is_zero_poison>)

<a id="id749"></a>

##### Overview:

The ‘`llvm.ctlz`’ family of intrinsic functions counts the number of leading zeros in a variable.

<a id="id750"></a>

##### Arguments:

The first argument is the value to be counted. This argument may be of any integer type, or a vector with integer element type. The return type must match the first argument type.

The second argument is a constant flag that indicates whether the intrinsic returns a valid result if the first argument is zero. If the first argument is zero and the second argument is true, the result is poison. Historically some architectures did not provide a defined result for zero values as efficiently, and many algorithms are now predicated on avoiding zero-value inputs.

<a id="id751"></a>

##### Semantics:

The ‘`llvm.ctlz`’ intrinsic counts the leading (most significant) zeros in a variable, or within each element of the vector. If `src == 0` then the result is the size in bits of the type of `src` if `is_zero_poison == 0` and `poison` otherwise. For example, `llvm.ctlz(i32 2) = 30`.

<a id="llvm-cttz-intrinsic"></a>

<a id="int-cttz"></a>

#### ‘`llvm.cttz.*`’ Intrinsic

<a id="id752"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.cttz` on any integer bit width, or any vector of integer elements. Not all targets support all bit widths or vector types, however.

    declare i42   @llvm.cttz.i42  (i42   <src>, i1 <is_zero_poison>)
    declare <2 x i32> @llvm.cttz.v2i32(<2 x i32> <src>, i1 <is_zero_poison>)

<a id="id753"></a>

##### Overview:

The ‘`llvm.cttz`’ family of intrinsic functions counts the number of trailing zeros.

<a id="id754"></a>

##### Arguments:

The first argument is the value to be counted. This argument may be of any integer type, or a vector with integer element type. The return type must match the first argument type.

The second argument is a constant flag that indicates whether the intrinsic returns a valid result if the first argument is zero. If the first argument is zero and the second argument is true, the result is poison. Historically some architectures did not provide a defined result for zero values as efficiently, and many algorithms are now predicated on avoiding zero-value inputs.

<a id="id755"></a>

##### Semantics:

The ‘`llvm.cttz`’ intrinsic counts the trailing (least significant) zeros in a variable, or within each element of a vector. If `src == 0` then the result is the size in bits of the type of `src` if `is_zero_poison == 0` and `poison` otherwise. For example, `llvm.cttz(2) = 1`.

<a id="llvm-fshl-intrinsic"></a>

<a id="int-fshl"></a>

#### ‘`llvm.fshl.*`’ Intrinsic

<a id="id756"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.fshl` on any integer bit width or any vector of integer elements. Not all targets support all bit widths or vector types, however.

    declare i8  @llvm.fshl.i8 (i8 %a, i8 %b, i8 %c)
    declare i64 @llvm.fshl.i64(i64 %a, i64 %b, i64 %c)
    declare <2 x i32> @llvm.fshl.v2i32(<2 x i32> %a, <2 x i32> %b, <2 x i32> %c)

<a id="id757"></a>

##### Overview:

The ‘`llvm.fshl`’ family of intrinsic functions performs a funnel shift left: the first two values are concatenated as { %a : %b } (%a is the most significant bits of the wide value), the combined value is shifted left, and the most significant bits are extracted to produce a result that is the same size as the original arguments. If the first 2 arguments are identical, this is equivalent to a rotate left operation. For vector types, the operation occurs for each element of the vector. The shift argument is treated as an unsigned amount modulo the element size of the arguments.

<a id="id758"></a>

##### Arguments:

The first two arguments are the values to be concatenated. The third argument is the shift amount. The arguments may be any integer type or a vector with integer element type. All arguments and the return value must have the same type.

<a id="id759"></a>

##### Example:

    %r = call i8 @llvm.fshl.i8(i8 %x, i8 %y, i8 %z)  ; %r = i8: msb_extract((concat(x, y) << (z % 8)), 8)
    %r = call i8 @llvm.fshl.i8(i8 255, i8 0, i8 15)  ; %r = i8: 128 (0b10000000)
    %r = call i8 @llvm.fshl.i8(i8 15, i8 15, i8 11)  ; %r = i8: 120 (0b01111000)
    %r = call i8 @llvm.fshl.i8(i8 0, i8 255, i8 8)   ; %r = i8: 0   (0b00000000)

<a id="llvm-fshr-intrinsic"></a>

<a id="int-fshr"></a>

#### ‘`llvm.fshr.*`’ Intrinsic

<a id="id760"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.fshr` on any integer bit width or any vector of integer elements. Not all targets support all bit widths or vector types, however.

    declare i8  @llvm.fshr.i8 (i8 %a, i8 %b, i8 %c)
    declare i64 @llvm.fshr.i64(i64 %a, i64 %b, i64 %c)
    declare <2 x i32> @llvm.fshr.v2i32(<2 x i32> %a, <2 x i32> %b, <2 x i32> %c)

<a id="id761"></a>

##### Overview:

The ‘`llvm.fshr`’ family of intrinsic functions performs a funnel shift right: the first two values are concatenated as { %a : %b } (%a is the most significant bits of the wide value), the combined value is shifted right, and the least significant bits are extracted to produce a result that is the same size as the original arguments. If the first 2 arguments are identical, this is equivalent to a rotate right operation. For vector types, the operation occurs for each element of the vector. The shift argument is treated as an unsigned amount modulo the element size of the arguments.

<a id="id762"></a>

##### Arguments:

The first two arguments are the values to be concatenated. The third argument is the shift amount. The arguments may be any integer type or a vector with integer element type. All arguments and the return value must have the same type.

<a id="id763"></a>

##### Example:

    %r = call i8 @llvm.fshr.i8(i8 %x, i8 %y, i8 %z)  ; %r = i8: lsb_extract((concat(x, y) >> (z % 8)), 8)
    %r = call i8 @llvm.fshr.i8(i8 255, i8 0, i8 15)  ; %r = i8: 254 (0b11111110)
    %r = call i8 @llvm.fshr.i8(i8 15, i8 15, i8 11)  ; %r = i8: 225 (0b11100001)
    %r = call i8 @llvm.fshr.i8(i8 0, i8 255, i8 8)   ; %r = i8: 255 (0b11111111)

<a id="llvm-clmul-intrinsic"></a>

<a id="int-clmul"></a>

#### ‘`llvm.clmul.*`’ Intrinsic

<a id="id764"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.clmul` on any integer or vectors of integer elements.

    declare i16 @llvm.clmul.i16(i16 %a, i16 %b)
    declare i32 @llvm.clmul.i32(i32 %a, i32 %b)
    declare i64 @llvm.clmul.i64(i64 %a, i64 %b)
    declare <4 x i32> @llvm.clmul.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id765"></a>

##### Overview:

The ‘`llvm.clmul`’ family of intrinsic functions performs carry-less multiplication, or XOR multiplication, on the two arguments, and returns the low-bits.

<a id="id766"></a>

##### Arguments:

The arguments may be any integer type or vector of integer type. Both arguments and result must have the same type.

<a id="id767"></a>

##### Semantics:

The ‘`llvm.clmul`’ intrinsic computes carry-less multiply of its arguments, which is the result of applying the standard multiplication algorithm, where all of the additions are replaced with XORs, and returns the low-bits. The vector variants operate lane-wise.

<a id="id768"></a>

##### Example:

    %r = call i4 @llvm.clmul.i4(i4 1, i4 2)    ; %r = 2
    %r = call i4 @llvm.clmul.i4(i4 5, i4 6)    ; %r = 14
    %r = call i4 @llvm.clmul.i4(i4 -4, i4 2)   ; %r = -8
    %r = call i4 @llvm.clmul.i4(i4 -4, i4 -5)  ; %r = 4

<a id="llvm-pext-intrinsic"></a>

<a id="int-pext"></a>

#### ‘`llvm.pext.*`’ Intrinsic

<a id="id769"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.pext` on any integer or integer vector type.

    declare i32 @llvm.pext.i32(i32 %val, i32 %mask)
    declare i64 @llvm.pext.i64(i64 %val, i64 %mask)
    declare <4 x i32> @llvm.pext.v4i32(<4 x i32> %val, <4 x i32> %mask)

<a id="id770"></a>

##### Overview:

The ‘`llvm.pext`’ family of intrinsic functions extracts the bits from `val` where the `mask` has bits set and packs them contiguously in the low bits of the result, same as the x86 `PEXT` instruction.

<a id="id771"></a>

##### Arguments:

The arguments may be any integer type or vector of integer type. Both arguments and result must have the same type.

<a id="id772"></a>

##### Semantics:

The ‘`llvm.pext`’ intrinsic extracts bits from the first argument `val` at the positions indicated by set bits in `mask`, and packs them contiguously into the low bits of the result. The remaining high bits of the result are zero.

Equivalently, if the set bit positions in `mask` (from LSB to MSB) are `p0, p1, ..., pk`, then the result bit `i` equals bit `pi` of `val`.

    %r = call i8 @llvm.pext.i8(i8 0b10101010, i8 0b11001100) ; %r = 0b00001010
    %r = call i8 @llvm.pext.i8(i8 0b11111111, i8 0b10101010) ; %r = 0b00001111

<a id="llvm-pdep-intrinsic"></a>

<a id="int-pdep"></a>

#### ‘`llvm.pdep.*`’ Intrinsic

<a id="id773"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.pdep` on any integer or integer vector type.

    declare i32 @llvm.pdep.i32(i32 %val, i32 %mask)
    declare i64 @llvm.pdep.i64(i64 %val, i64 %mask)
    declare <4 x i32> @llvm.pdep.v4i32(<4 x i32> %val, <4 x i32> %mask)

<a id="id774"></a>

##### Overview:

The ‘`llvm.pdep`’ family of intrinsic functions deposits the low bits of `val` into the result at the positions where `mask` has bits set, same as the x86 `PDEP` instruction.

<a id="id775"></a>

##### Arguments:

The arguments may be any integer type or vector of integer type. Both arguments and result must have the same type.

<a id="id776"></a>

##### Semantics:

The ‘`llvm.pdep`’ intrinsic takes the low bits of the first argument `val` and scatters them to the bit positions in the result indicated by set bits in `mask`. Bits in the result at positions where `mask` is zero are zero.

Equivalently, if the set bit positions in `mask` (from LSB to MSB) are `p0, p1, ..., pk`, then result bit `pi` equals bit `i` of `val`.

The operations satisfy the round-trip identity: `pdep(pext(val, mask), mask) == val & mask`.

    %r = call i8 @llvm.pdep.i8(i8 0b00001010, i8 0b11001100) ; %r = 0b10001000
    %r = call i8 @llvm.pdep.i8(i8 0b00001111, i8 0b10101010) ; %r = 0b10101010

<a id="arithmetic-with-overflow-intrinsics"></a>

<a id="int-overflow"></a>

### Arithmetic with Overflow Intrinsics

LLVM provides intrinsics for fast arithmetic overflow checking.

Each of these intrinsics returns a two-element struct. The first element of this struct contains the result of the corresponding arithmetic operation modulo 2<sup>n</sup>, where n is the bit width of the result. Therefore, for example, the first element of the struct returned by `llvm.sadd.with.overflow.i32` is always the same as the result of a 32-bit `add` instruction with the same operands, where the `add` is *not* modified by an `nsw` or `nuw` flag.

The second element of the result is an `i1` that is 1 if the arithmetic operation overflowed and 0 otherwise. An operation overflows if, for any values of its operands `A` and `B` and for any `N` larger than the operands’ width, `ext(A op B) to iN` is not equal to `(ext(A) to iN) op (ext(B) to iN)` where `ext` is `sext` for signed overflow and `zext` for unsigned overflow, and `op` is the underlying arithmetic operation.

The behavior of these intrinsics is well-defined for all argument values.

<a id="llvm-sadd-with-overflow-intrinsics"></a>

#### ‘`llvm.sadd.with.overflow.*`’ Intrinsics

<a id="id777"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.sadd.with.overflow` on any integer bit width or vectors of integers.

    declare {i16, i1} @llvm.sadd.with.overflow.i16(i16 %a, i16 %b)
    declare {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
    declare {i64, i1} @llvm.sadd.with.overflow.i64(i64 %a, i64 %b)
    declare {<4 x i32>, <4 x i1>} @llvm.sadd.with.overflow.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id778"></a>

##### Overview:

The ‘`llvm.sadd.with.overflow`’ family of intrinsic functions perform a signed addition of the two arguments, and indicate whether an overflow occurred during the signed summation.

<a id="id779"></a>

##### Arguments:

The arguments (%a and %b) and the first element of the result structure may be of integer types of any bit width, but they must have the same bit width. The second element of the result structure must be of type `i1`. `%a` and `%b` are the two values that will undergo signed addition.

<a id="id780"></a>

##### Semantics:

The ‘`llvm.sadd.with.overflow`’ family of intrinsic functions perform a signed addition of the two variables. They return a structure — the first element of which is the signed summation, and the second element of which is a bit specifying if the signed summation resulted in an overflow.

<a id="id781"></a>

##### Examples:

    %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
    %sum = extractvalue {i32, i1} %res, 0
    %obit = extractvalue {i32, i1} %res, 1
    br i1 %obit, label %overflow, label %normal

<a id="llvm-uadd-with-overflow-intrinsics"></a>

#### ‘`llvm.uadd.with.overflow.*`’ Intrinsics

<a id="id782"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.uadd.with.overflow` on any integer bit width or vectors of integers.

    declare {i16, i1} @llvm.uadd.with.overflow.i16(i16 %a, i16 %b)
    declare {i32, i1} @llvm.uadd.with.overflow.i32(i32 %a, i32 %b)
    declare {i64, i1} @llvm.uadd.with.overflow.i64(i64 %a, i64 %b)
    declare {<4 x i32>, <4 x i1>} @llvm.uadd.with.overflow.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id783"></a>

##### Overview:

The ‘`llvm.uadd.with.overflow`’ family of intrinsic functions perform an unsigned addition of the two arguments, and indicate whether a carry occurred during the unsigned summation.

<a id="id784"></a>

##### Arguments:

The arguments (%a and %b) and the first element of the result structure may be of integer types of any bit width, but they must have the same bit width. The second element of the result structure must be of type `i1`. `%a` and `%b` are the two values that will undergo unsigned addition.

<a id="id785"></a>

##### Semantics:

The ‘`llvm.uadd.with.overflow`’ family of intrinsic functions perform an unsigned addition of the two arguments. They return a structure — the first element of which is the sum, and the second element of which is a bit specifying if the unsigned summation resulted in a carry.

<a id="id786"></a>

##### Examples:

    %res = call {i32, i1} @llvm.uadd.with.overflow.i32(i32 %a, i32 %b)
    %sum = extractvalue {i32, i1} %res, 0
    %obit = extractvalue {i32, i1} %res, 1
    br i1 %obit, label %carry, label %normal

<a id="llvm-ssub-with-overflow-intrinsics"></a>

#### ‘`llvm.ssub.with.overflow.*`’ Intrinsics

<a id="id787"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.ssub.with.overflow` on any integer bit width or vectors of integers.

    declare {i16, i1} @llvm.ssub.with.overflow.i16(i16 %a, i16 %b)
    declare {i32, i1} @llvm.ssub.with.overflow.i32(i32 %a, i32 %b)
    declare {i64, i1} @llvm.ssub.with.overflow.i64(i64 %a, i64 %b)
    declare {<4 x i32>, <4 x i1>} @llvm.ssub.with.overflow.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id788"></a>

##### Overview:

The ‘`llvm.ssub.with.overflow`’ family of intrinsic functions perform a signed subtraction of the two arguments, and indicate whether an overflow occurred during the signed subtraction.

<a id="id789"></a>

##### Arguments:

The arguments (%a and %b) and the first element of the result structure may be of integer types of any bit width, but they must have the same bit width. The second element of the result structure must be of type `i1`. `%a` and `%b` are the two values that will undergo signed subtraction.

<a id="id790"></a>

##### Semantics:

The ‘`llvm.ssub.with.overflow`’ family of intrinsic functions perform a signed subtraction of the two arguments. They return a structure — the first element of which is the subtraction, and the second element of which is a bit specifying if the signed subtraction resulted in an overflow.

<a id="id791"></a>

##### Examples:

    %res = call {i32, i1} @llvm.ssub.with.overflow.i32(i32 %a, i32 %b)
    %sum = extractvalue {i32, i1} %res, 0
    %obit = extractvalue {i32, i1} %res, 1
    br i1 %obit, label %overflow, label %normal

<a id="llvm-usub-with-overflow-intrinsics"></a>

#### ‘`llvm.usub.with.overflow.*`’ Intrinsics

<a id="id792"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.usub.with.overflow` on any integer bit width or vectors of integers.

    declare {i16, i1} @llvm.usub.with.overflow.i16(i16 %a, i16 %b)
    declare {i32, i1} @llvm.usub.with.overflow.i32(i32 %a, i32 %b)
    declare {i64, i1} @llvm.usub.with.overflow.i64(i64 %a, i64 %b)
    declare {<4 x i32>, <4 x i1>} @llvm.usub.with.overflow.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id793"></a>

##### Overview:

The ‘`llvm.usub.with.overflow`’ family of intrinsic functions perform an unsigned subtraction of the two arguments, and indicate whether an overflow occurred during the unsigned subtraction.

<a id="id794"></a>

##### Arguments:

The arguments (%a and %b) and the first element of the result structure may be of integer types of any bit width, but they must have the same bit width. The second element of the result structure must be of type `i1`. `%a` and `%b` are the two values that will undergo unsigned subtraction.

<a id="id795"></a>

##### Semantics:

The ‘`llvm.usub.with.overflow`’ family of intrinsic functions perform an unsigned subtraction of the two arguments. They return a structure — the first element of which is the subtraction, and the second element of which is a bit specifying if the unsigned subtraction resulted in an overflow.

<a id="id796"></a>

##### Examples:

    %res = call {i32, i1} @llvm.usub.with.overflow.i32(i32 %a, i32 %b)
    %sum = extractvalue {i32, i1} %res, 0
    %obit = extractvalue {i32, i1} %res, 1
    br i1 %obit, label %overflow, label %normal

<a id="llvm-smul-with-overflow-intrinsics"></a>

#### ‘`llvm.smul.with.overflow.*`’ Intrinsics

<a id="id797"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.smul.with.overflow` on any integer bit width or vectors of integers.

    declare {i16, i1} @llvm.smul.with.overflow.i16(i16 %a, i16 %b)
    declare {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)
    declare {i64, i1} @llvm.smul.with.overflow.i64(i64 %a, i64 %b)
    declare {<4 x i32>, <4 x i1>} @llvm.smul.with.overflow.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id798"></a>

##### Overview:

The ‘`llvm.smul.with.overflow`’ family of intrinsic functions perform a signed multiplication of the two arguments, and indicate whether an overflow occurred during the signed multiplication.

<a id="id799"></a>

##### Arguments:

The arguments (%a and %b) and the first element of the result structure may be of integer types of any bit width, but they must have the same bit width. The second element of the result structure must be of type `i1`. `%a` and `%b` are the two values that will undergo signed multiplication.

<a id="id800"></a>

##### Semantics:

The ‘`llvm.smul.with.overflow`’ family of intrinsic functions perform a signed multiplication of the two arguments. They return a structure — the first element of which is the multiplication, and the second element of which is a bit specifying if the signed multiplication resulted in an overflow.

<a id="id801"></a>

##### Examples:

    %res = call {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)
    %sum = extractvalue {i32, i1} %res, 0
    %obit = extractvalue {i32, i1} %res, 1
    br i1 %obit, label %overflow, label %normal

<a id="llvm-umul-with-overflow-intrinsics"></a>

#### ‘`llvm.umul.with.overflow.*`’ Intrinsics

<a id="id802"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.umul.with.overflow` on any integer bit width or vectors of integers.

    declare {i16, i1} @llvm.umul.with.overflow.i16(i16 %a, i16 %b)
    declare {i32, i1} @llvm.umul.with.overflow.i32(i32 %a, i32 %b)
    declare {i64, i1} @llvm.umul.with.overflow.i64(i64 %a, i64 %b)
    declare {<4 x i32>, <4 x i1>} @llvm.umul.with.overflow.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id803"></a>

##### Overview:

The ‘`llvm.umul.with.overflow`’ family of intrinsic functions perform an unsigned multiplication of the two arguments, and indicate whether an overflow occurred during the unsigned multiplication.

<a id="id804"></a>

##### Arguments:

The arguments (%a and %b) and the first element of the result structure may be of integer types of any bit width, but they must have the same bit width. The second element of the result structure must be of type `i1`. `%a` and `%b` are the two values that will undergo unsigned multiplication.

<a id="id805"></a>

##### Semantics:

The ‘`llvm.umul.with.overflow`’ family of intrinsic functions perform an unsigned multiplication of the two arguments. They return a structure — the first element of which is the multiplication, and the second element of which is a bit specifying if the unsigned multiplication resulted in an overflow.

<a id="id806"></a>

##### Examples:

    %res = call {i32, i1} @llvm.umul.with.overflow.i32(i32 %a, i32 %b)
    %sum = extractvalue {i32, i1} %res, 0
    %obit = extractvalue {i32, i1} %res, 1
    br i1 %obit, label %overflow, label %normal

<a id="saturation-arithmetic-intrinsics"></a>

### Saturation Arithmetic Intrinsics

Saturation arithmetic is a version of arithmetic in which operations are limited to a fixed range between a minimum and maximum value. If the result of an operation is greater than the maximum value, the result is set (or “clamped”) to this maximum. If it is below the minimum, it is clamped to this minimum.

<a id="llvm-sadd-sat-intrinsics"></a>

<a id="int-sadd-sat"></a>

#### ‘`llvm.sadd.sat.*`’ Intrinsics

<a id="id807"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.sadd.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.sadd.sat.i16(i16 %a, i16 %b)
    declare i32 @llvm.sadd.sat.i32(i32 %a, i32 %b)
    declare i64 @llvm.sadd.sat.i64(i64 %a, i64 %b)
    declare <4 x i32> @llvm.sadd.sat.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id808"></a>

##### Overview

The ‘`llvm.sadd.sat`’ family of intrinsic functions perform signed saturating addition on the 2 arguments.

<a id="id809"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo signed addition.

<a id="id810"></a>

##### Semantics:

The maximum value this operation can clamp to is the largest signed value representable by the bit width of the arguments. The minimum value is the smallest signed value representable by this bit width.

<a id="id811"></a>

##### Examples

    %res = call i4 @llvm.sadd.sat.i4(i4 1, i4 2)  ; %res = 3
    %res = call i4 @llvm.sadd.sat.i4(i4 5, i4 6)  ; %res = 7
    %res = call i4 @llvm.sadd.sat.i4(i4 -4, i4 2)  ; %res = -2
    %res = call i4 @llvm.sadd.sat.i4(i4 -4, i4 -5)  ; %res = -8

<a id="llvm-uadd-sat-intrinsics"></a>

<a id="int-uadd-sat"></a>

#### ‘`llvm.uadd.sat.*`’ Intrinsics

<a id="id812"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.uadd.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.uadd.sat.i16(i16 %a, i16 %b)
    declare i32 @llvm.uadd.sat.i32(i32 %a, i32 %b)
    declare i64 @llvm.uadd.sat.i64(i64 %a, i64 %b)
    declare <4 x i32> @llvm.uadd.sat.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id813"></a>

##### Overview

The ‘`llvm.uadd.sat`’ family of intrinsic functions perform unsigned saturating addition on the 2 arguments.

<a id="id814"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo unsigned addition.

<a id="id815"></a>

##### Semantics:

The maximum value this operation can clamp to is the largest unsigned value representable by the bit width of the arguments. Because this is an unsigned operation, the result will never saturate towards zero.

<a id="id816"></a>

##### Examples

    %res = call i4 @llvm.uadd.sat.i4(i4 1, i4 2)  ; %res = 3
    %res = call i4 @llvm.uadd.sat.i4(i4 5, i4 6)  ; %res = 11
    %res = call i4 @llvm.uadd.sat.i4(i4 8, i4 8)  ; %res = 15

<a id="llvm-ssub-sat-intrinsics"></a>

<a id="int-ssub-sat"></a>

#### ‘`llvm.ssub.sat.*`’ Intrinsics

<a id="id817"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.ssub.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.ssub.sat.i16(i16 %a, i16 %b)
    declare i32 @llvm.ssub.sat.i32(i32 %a, i32 %b)
    declare i64 @llvm.ssub.sat.i64(i64 %a, i64 %b)
    declare <4 x i32> @llvm.ssub.sat.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id818"></a>

##### Overview

The ‘`llvm.ssub.sat`’ family of intrinsic functions perform signed saturating subtraction on the 2 arguments.

<a id="id819"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo signed subtraction.

<a id="id820"></a>

##### Semantics:

The maximum value this operation can clamp to is the largest signed value representable by the bit width of the arguments. The minimum value is the smallest signed value representable by this bit width.

<a id="id821"></a>

##### Examples

    %res = call i4 @llvm.ssub.sat.i4(i4 2, i4 1)  ; %res = 1
    %res = call i4 @llvm.ssub.sat.i4(i4 2, i4 6)  ; %res = -4
    %res = call i4 @llvm.ssub.sat.i4(i4 -4, i4 5)  ; %res = -8
    %res = call i4 @llvm.ssub.sat.i4(i4 4, i4 -5)  ; %res = 7

<a id="llvm-usub-sat-intrinsics"></a>

<a id="int-usub-sat"></a>

#### ‘`llvm.usub.sat.*`’ Intrinsics

<a id="id822"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.usub.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.usub.sat.i16(i16 %a, i16 %b)
    declare i32 @llvm.usub.sat.i32(i32 %a, i32 %b)
    declare i64 @llvm.usub.sat.i64(i64 %a, i64 %b)
    declare <4 x i32> @llvm.usub.sat.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id823"></a>

##### Overview

The ‘`llvm.usub.sat`’ family of intrinsic functions perform unsigned saturating subtraction on the 2 arguments.

<a id="id824"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo unsigned subtraction.

<a id="id825"></a>

##### Semantics:

The minimum value this operation can clamp to is 0, which is the smallest unsigned value representable by the bit width of the unsigned arguments. Because this is an unsigned operation, the result will never saturate towards the largest possible value representable by this bit width.

<a id="id826"></a>

##### Examples

    %res = call i4 @llvm.usub.sat.i4(i4 2, i4 1)  ; %res = 1
    %res = call i4 @llvm.usub.sat.i4(i4 2, i4 6)  ; %res = 0

<a id="llvm-sshl-sat-intrinsics"></a>

#### ‘`llvm.sshl.sat.*`’ Intrinsics

<a id="id827"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.sshl.sat` on integers or vectors of integers of any bit width.

    declare i16 @llvm.sshl.sat.i16(i16 %a, i16 %b)
    declare i32 @llvm.sshl.sat.i32(i32 %a, i32 %b)
    declare i64 @llvm.sshl.sat.i64(i64 %a, i64 %b)
    declare <4 x i32> @llvm.sshl.sat.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id828"></a>

##### Overview

The ‘`llvm.sshl.sat`’ family of intrinsic functions perform signed saturating left shift on the first argument.

<a id="id829"></a>

##### Arguments

The arguments (`%a` and `%b`) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` is the value to be shifted, and `%b` is the amount to shift by. If `b` is (statically or dynamically) equal to or larger than the integer bit width of the arguments, the result is a [poison value](constants.md#poisonvalues). If the arguments are vectors, each vector element of `a` is shifted by the corresponding shift amount in `b`.

<a id="id830"></a>

##### Semantics:

The maximum value this operation can clamp to is the largest signed value representable by the bit width of the arguments. The minimum value is the smallest signed value representable by this bit width.

<a id="id831"></a>

##### Examples

    %res = call i4 @llvm.sshl.sat.i4(i4 2, i4 1)  ; %res = 4
    %res = call i4 @llvm.sshl.sat.i4(i4 2, i4 2)  ; %res = 7
    %res = call i4 @llvm.sshl.sat.i4(i4 -5, i4 1)  ; %res = -8
    %res = call i4 @llvm.sshl.sat.i4(i4 -1, i4 1)  ; %res = -2

<a id="llvm-ushl-sat-intrinsics"></a>

#### ‘`llvm.ushl.sat.*`’ Intrinsics

<a id="id832"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.ushl.sat` on integers or vectors of integers of any bit width.

    declare i16 @llvm.ushl.sat.i16(i16 %a, i16 %b)
    declare i32 @llvm.ushl.sat.i32(i32 %a, i32 %b)
    declare i64 @llvm.ushl.sat.i64(i64 %a, i64 %b)
    declare <4 x i32> @llvm.ushl.sat.v4i32(<4 x i32> %a, <4 x i32> %b)

<a id="id833"></a>

##### Overview

The ‘`llvm.ushl.sat`’ family of intrinsic functions perform unsigned saturating left shift on the first argument.

<a id="id834"></a>

##### Arguments

The arguments (`%a` and `%b`) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` is the value to be shifted, and `%b` is the amount to shift by. If `b` is (statically or dynamically) equal to or larger than the integer bit width of the arguments, the result is a [poison value](constants.md#poisonvalues). If the arguments are vectors, each vector element of `a` is shifted by the corresponding shift amount in `b`.

<a id="id835"></a>

##### Semantics:

The maximum value this operation can clamp to is the largest unsigned value representable by the bit width of the arguments.

<a id="id836"></a>

##### Examples

    %res = call i4 @llvm.ushl.sat.i4(i4 2, i4 1)  ; %res = 4
    %res = call i4 @llvm.ushl.sat.i4(i4 3, i4 3)  ; %res = 15

<a id="fixed-point-arithmetic-intrinsics"></a>

### Fixed Point Arithmetic Intrinsics

A fixed point number represents a real data type for a number that has a fixed number of digits after a radix point (equivalent to the decimal point ‘.’). The number of digits after the radix point is referred as the `scale`. These are useful for representing fractional values to a specific precision. The following intrinsics perform fixed point arithmetic operations on 2 operands of the same scale, specified as the third argument.

The `llvm.*mul.fix` family of intrinsic functions represents a multiplication of fixed point numbers through scaled integers. Therefore, fixed point multiplication can be represented as

    %result = call i4 @llvm.smul.fix.i4(i4 %a, i4 %b, i32 %scale)

    ; Expands to
    %a2 = sext i4 %a to i8
    %b2 = sext i4 %b to i8
    %mul = mul nsw nuw i8 %a2, %b2
    %scale2 = trunc i32 %scale to i8
    %r = ashr i8 %mul, i8 %scale2  ; this is for a target rounding down towards negative infinity
    %result = trunc i8 %r to i4

The `llvm.*div.fix` family of intrinsic functions represents a division of fixed point numbers through scaled integers. Fixed point division can be represented as:

    %result call i4 @llvm.sdiv.fix.i4(i4 %a, i4 %b, i32 %scale)

    ; Expands to
    %a2 = sext i4 %a to i8
    %b2 = sext i4 %b to i8
    %scale2 = trunc i32 %scale to i8
    %a3 = shl i8 %a2, %scale2
    %r = sdiv i8 %a3, %b2 ; this is for a target rounding towards zero
    %result = trunc i8 %r to i4

For each of these functions, if the result cannot be represented exactly with the provided scale, the result is rounded. Rounding is unspecified since preferred rounding may vary for different targets. Rounding is specified through a target hook. Different pipelines should legalize or optimize this using the rounding specified by this hook if it is provided. Operations like constant folding, instruction combining, KnownBits, and ValueTracking should also use this hook, if provided, and not assume the direction of rounding. A rounded result must always be within one unit of precision from the true result. That is, the error between the returned result and the true result must be less than 1/2^(scale).

<a id="llvm-smul-fix-intrinsics"></a>

#### ‘`llvm.smul.fix.*`’ Intrinsics

<a id="id837"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.smul.fix` on any integer bit width or vectors of integers.

    declare i16 @llvm.smul.fix.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.smul.fix.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.smul.fix.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.smul.fix.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id838"></a>

##### Overview

The ‘`llvm.smul.fix`’ family of intrinsic functions perform signed fixed point multiplication on 2 arguments of the same scale.

<a id="id839"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. The arguments may also work with int vectors of the same length and int size. `%a` and `%b` are the two values that will undergo signed fixed point multiplication. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id840"></a>

##### Semantics:

This operation performs fixed point multiplication on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

It is undefined behavior if the result value does not fit within the range of the fixed point type.

<a id="id841"></a>

##### Examples

    %res = call i4 @llvm.smul.fix.i4(i4 3, i4 2, i32 0)  ; %res = 6 (2 x 3 = 6)
    %res = call i4 @llvm.smul.fix.i4(i4 3, i4 2, i32 1)  ; %res = 3 (1.5 x 1 = 1.5)
    %res = call i4 @llvm.smul.fix.i4(i4 3, i4 -2, i32 1)  ; %res = -3 (1.5 x -1 = -1.5)

    ; The result in the following could be rounded up to -2 or down to -2.5
    %res = call i4 @llvm.smul.fix.i4(i4 3, i4 -3, i32 1)  ; %res = -5 (or -4) (1.5 x -1.5 = -2.25)

<a id="llvm-umul-fix-intrinsics"></a>

#### ‘`llvm.umul.fix.*`’ Intrinsics

<a id="id842"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.umul.fix` on any integer bit width or vectors of integers.

    declare i16 @llvm.umul.fix.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.umul.fix.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.umul.fix.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.umul.fix.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id843"></a>

##### Overview

The ‘`llvm.umul.fix`’ family of intrinsic functions perform unsigned fixed point multiplication on 2 arguments of the same scale.

<a id="id844"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. The arguments may also work with int vectors of the same length and int size. `%a` and `%b` are the two values that will undergo unsigned fixed point multiplication. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id845"></a>

##### Semantics:

This operation performs unsigned fixed point multiplication on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

It is undefined behavior if the result value does not fit within the range of the fixed point type.

<a id="id846"></a>

##### Examples

    %res = call i4 @llvm.umul.fix.i4(i4 3, i4 2, i32 0)  ; %res = 6 (2 x 3 = 6)
    %res = call i4 @llvm.umul.fix.i4(i4 3, i4 2, i32 1)  ; %res = 3 (1.5 x 1 = 1.5)

    ; The result in the following could be rounded down to 3.5 or up to 4
    %res = call i4 @llvm.umul.fix.i4(i4 15, i4 1, i32 1)  ; %res = 7 (or 8) (7.5 x 0.5 = 3.75)

<a id="llvm-smul-fix-sat-intrinsics"></a>

#### ‘`llvm.smul.fix.sat.*`’ Intrinsics

<a id="id847"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.smul.fix.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.smul.fix.sat.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.smul.fix.sat.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.smul.fix.sat.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.smul.fix.sat.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id848"></a>

##### Overview

The ‘`llvm.smul.fix.sat`’ family of intrinsic functions perform signed fixed point saturating multiplication on 2 arguments of the same scale.

<a id="id849"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo signed fixed point multiplication. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id850"></a>

##### Semantics:

This operation performs fixed point multiplication on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

The maximum value this operation can clamp to is the largest signed value representable by the bit width of the first 2 arguments. The minimum value is the smallest signed value representable by this bit width.

<a id="id851"></a>

##### Examples

    %res = call i4 @llvm.smul.fix.sat.i4(i4 3, i4 2, i32 0)  ; %res = 6 (2 x 3 = 6)
    %res = call i4 @llvm.smul.fix.sat.i4(i4 3, i4 2, i32 1)  ; %res = 3 (1.5 x 1 = 1.5)
    %res = call i4 @llvm.smul.fix.sat.i4(i4 3, i4 -2, i32 1)  ; %res = -3 (1.5 x -1 = -1.5)

    ; The result in the following could be rounded up to -2 or down to -2.5
    %res = call i4 @llvm.smul.fix.sat.i4(i4 3, i4 -3, i32 1)  ; %res = -5 (or -4) (1.5 x -1.5 = -2.25)

    ; Saturation
    %res = call i4 @llvm.smul.fix.sat.i4(i4 7, i4 2, i32 0)  ; %res = 7
    %res = call i4 @llvm.smul.fix.sat.i4(i4 7, i4 4, i32 2)  ; %res = 7
    %res = call i4 @llvm.smul.fix.sat.i4(i4 -8, i4 5, i32 2)  ; %res = -8
    %res = call i4 @llvm.smul.fix.sat.i4(i4 -8, i4 -2, i32 1)  ; %res = 7

    ; Scale can affect the saturation result
    %res = call i4 @llvm.smul.fix.sat.i4(i4 2, i4 4, i32 0)  ; %res = 7 (2 x 4 -> clamped to 7)
    %res = call i4 @llvm.smul.fix.sat.i4(i4 2, i4 4, i32 1)  ; %res = 4 (1 x 2 = 2)

<a id="llvm-umul-fix-sat-intrinsics"></a>

#### ‘`llvm.umul.fix.sat.*`’ Intrinsics

<a id="id852"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.umul.fix.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.umul.fix.sat.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.umul.fix.sat.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.umul.fix.sat.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.umul.fix.sat.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id853"></a>

##### Overview

The ‘`llvm.umul.fix.sat`’ family of intrinsic functions perform unsigned fixed point saturating multiplication on 2 arguments of the same scale.

<a id="id854"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo unsigned fixed point multiplication. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id855"></a>

##### Semantics:

This operation performs fixed point multiplication on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

The maximum value this operation can clamp to is the largest unsigned value representable by the bit width of the first 2 arguments. The minimum value is the smallest unsigned value representable by this bit width (zero).

<a id="id856"></a>

##### Examples

    %res = call i4 @llvm.umul.fix.sat.i4(i4 3, i4 2, i32 0)  ; %res = 6 (2 x 3 = 6)
    %res = call i4 @llvm.umul.fix.sat.i4(i4 3, i4 2, i32 1)  ; %res = 3 (1.5 x 1 = 1.5)

    ; The result in the following could be rounded down to 2 or up to 2.5
    %res = call i4 @llvm.umul.fix.sat.i4(i4 3, i4 3, i32 1)  ; %res = 4 (or 5) (1.5 x 1.5 = 2.25)

    ; Saturation
    %res = call i4 @llvm.umul.fix.sat.i4(i4 8, i4 2, i32 0)  ; %res = 15 (8 x 2 -> clamped to 15)
    %res = call i4 @llvm.umul.fix.sat.i4(i4 8, i4 8, i32 2)  ; %res = 15 (2 x 2 -> clamped to 3.75)

    ; Scale can affect the saturation result
    %res = call i4 @llvm.umul.fix.sat.i4(i4 2, i4 4, i32 0)  ; %res = 7 (2 x 4 -> clamped to 7)
    %res = call i4 @llvm.umul.fix.sat.i4(i4 2, i4 4, i32 1)  ; %res = 4 (1 x 2 = 2)

<a id="llvm-sdiv-fix-intrinsics"></a>

#### ‘`llvm.sdiv.fix.*`’ Intrinsics

<a id="id857"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.sdiv.fix` on any integer bit width or vectors of integers.

    declare i16 @llvm.sdiv.fix.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.sdiv.fix.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.sdiv.fix.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.sdiv.fix.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id858"></a>

##### Overview

The ‘`llvm.sdiv.fix`’ family of intrinsic functions perform signed fixed point division on 2 arguments of the same scale.

<a id="id859"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. The arguments may also work with int vectors of the same length and int size. `%a` and `%b` are the two values that will undergo signed fixed point division. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id860"></a>

##### Semantics:

This operation performs fixed point division on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

It is undefined behavior if the result value does not fit within the range of the fixed point type, or if the second argument is zero.

<a id="id861"></a>

##### Examples

    %res = call i4 @llvm.sdiv.fix.i4(i4 6, i4 2, i32 0)  ; %res = 3 (6 / 2 = 3)
    %res = call i4 @llvm.sdiv.fix.i4(i4 6, i4 4, i32 1)  ; %res = 3 (3 / 2 = 1.5)
    %res = call i4 @llvm.sdiv.fix.i4(i4 3, i4 -2, i32 1) ; %res = -3 (1.5 / -1 = -1.5)

    ; The result in the following could be rounded up to 1 or down to 0.5
    %res = call i4 @llvm.sdiv.fix.i4(i4 3, i4 4, i32 1)  ; %res = 2 (or 1) (1.5 / 2 = 0.75)

<a id="llvm-udiv-fix-intrinsics"></a>

#### ‘`llvm.udiv.fix.*`’ Intrinsics

<a id="id862"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.udiv.fix` on any integer bit width or vectors of integers.

    declare i16 @llvm.udiv.fix.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.udiv.fix.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.udiv.fix.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.udiv.fix.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id863"></a>

##### Overview

The ‘`llvm.udiv.fix`’ family of intrinsic functions perform unsigned fixed point division on 2 arguments of the same scale.

<a id="id864"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. The arguments may also work with int vectors of the same length and int size. `%a` and `%b` are the two values that will undergo unsigned fixed point division. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id865"></a>

##### Semantics:

This operation performs fixed point division on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

It is undefined behavior if the result value does not fit within the range of the fixed point type, or if the second argument is zero.

<a id="id866"></a>

##### Examples

    %res = call i4 @llvm.udiv.fix.i4(i4 6, i4 2, i32 0)  ; %res = 3 (6 / 2 = 3)
    %res = call i4 @llvm.udiv.fix.i4(i4 6, i4 4, i32 1)  ; %res = 3 (3 / 2 = 1.5)
    %res = call i4 @llvm.udiv.fix.i4(i4 1, i4 -8, i32 4) ; %res = 2 (0.0625 / 0.5 = 0.125)

    ; The result in the following could be rounded up to 1 or down to 0.5
    %res = call i4 @llvm.udiv.fix.i4(i4 3, i4 4, i32 1)  ; %res = 2 (or 1) (1.5 / 2 = 0.75)

<a id="llvm-sdiv-fix-sat-intrinsics"></a>

#### ‘`llvm.sdiv.fix.sat.*`’ Intrinsics

<a id="id867"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.sdiv.fix.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.sdiv.fix.sat.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.sdiv.fix.sat.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.sdiv.fix.sat.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.sdiv.fix.sat.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id868"></a>

##### Overview

The ‘`llvm.sdiv.fix.sat`’ family of intrinsic functions perform signed fixed point saturating division on 2 arguments of the same scale.

<a id="id869"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo signed fixed point division. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id870"></a>

##### Semantics:

This operation performs fixed point division on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

The maximum value this operation can clamp to is the largest signed value representable by the bit width of the first 2 arguments. The minimum value is the smallest signed value representable by this bit width.

It is undefined behavior if the second argument is zero.

<a id="id871"></a>

##### Examples

    %res = call i4 @llvm.sdiv.fix.sat.i4(i4 6, i4 2, i32 0)  ; %res = 3 (6 / 2 = 3)
    %res = call i4 @llvm.sdiv.fix.sat.i4(i4 6, i4 4, i32 1)  ; %res = 3 (3 / 2 = 1.5)
    %res = call i4 @llvm.sdiv.fix.sat.i4(i4 3, i4 -2, i32 1) ; %res = -3 (1.5 / -1 = -1.5)

    ; The result in the following could be rounded up to 1 or down to 0.5
    %res = call i4 @llvm.sdiv.fix.sat.i4(i4 3, i4 4, i32 1)  ; %res = 2 (or 1) (1.5 / 2 = 0.75)

    ; Saturation
    %res = call i4 @llvm.sdiv.fix.sat.i4(i4 -8, i4 -1, i32 0)  ; %res = 7 (-8 / -1 = 8 => 7)
    %res = call i4 @llvm.sdiv.fix.sat.i4(i4 4, i4 2, i32 2)  ; %res = 7 (1 / 0.5 = 2 => 1.75)
    %res = call i4 @llvm.sdiv.fix.sat.i4(i4 -4, i4 1, i32 2)  ; %res = -8 (-1 / 0.25 = -4 => -2)

<a id="llvm-udiv-fix-sat-intrinsics"></a>

#### ‘`llvm.udiv.fix.sat.*`’ Intrinsics

<a id="id872"></a>

##### Syntax

This is an overloaded intrinsic. You can use `llvm.udiv.fix.sat` on any integer bit width or vectors of integers.

    declare i16 @llvm.udiv.fix.sat.i16(i16 %a, i16 %b, i32 %scale)
    declare i32 @llvm.udiv.fix.sat.i32(i32 %a, i32 %b, i32 %scale)
    declare i64 @llvm.udiv.fix.sat.i64(i64 %a, i64 %b, i32 %scale)
    declare <4 x i32> @llvm.udiv.fix.sat.v4i32(<4 x i32> %a, <4 x i32> %b, i32 %scale)

<a id="id873"></a>

##### Overview

The ‘`llvm.udiv.fix.sat`’ family of intrinsic functions perform unsigned fixed point saturating division on 2 arguments of the same scale.

<a id="id874"></a>

##### Arguments

The arguments (%a and %b) and the result may be of integer types of any bit width, but they must have the same bit width. `%a` and `%b` are the two values that will undergo unsigned fixed point division. The argument `%scale` represents the scale of both operands, and must be a constant integer.

<a id="id875"></a>

##### Semantics:

This operation performs fixed point division on the 2 arguments of a specified scale. The result will also be returned in the same scale specified in the third argument.

If the result value cannot be precisely represented in the given scale, the value is rounded up or down to the closest representable value. The rounding direction is unspecified.

The maximum value this operation can clamp to is the largest unsigned value representable by the bit width of the first 2 arguments. The minimum value is the smallest unsigned value representable by this bit width (zero).

It is undefined behavior if the second argument is zero.

<a id="id876"></a>

##### Examples

    %res = call i4 @llvm.udiv.fix.sat.i4(i4 6, i4 2, i32 0)  ; %res = 3 (6 / 2 = 3)
    %res = call i4 @llvm.udiv.fix.sat.i4(i4 6, i4 4, i32 1)  ; %res = 3 (3 / 2 = 1.5)

    ; The result in the following could be rounded down to 0.5 or up to 1
    %res = call i4 @llvm.udiv.fix.sat.i4(i4 3, i4 4, i32 1)  ; %res = 1 (or 2) (1.5 / 2 = 0.75)

    ; Saturation
    %res = call i4 @llvm.udiv.fix.sat.i4(i4 8, i4 2, i32 2)  ; %res = 15 (2 / 0.5 = 4 => 3.75)

<a id="specialized-arithmetic-intrinsics"></a>

### Specialized Arithmetic Intrinsics

<a id="llvm-canonicalize-intrinsic"></a>

<a id="i-intr-llvm-canonicalize"></a>

#### ‘`llvm.canonicalize.*`’ Intrinsic

<a id="id877"></a>

##### Syntax:

    declare float @llvm.canonicalize.f32(float %a)
    declare double @llvm.canonicalize.f64(double %b)

<a id="id878"></a>

##### Overview:

The ‘`llvm.canonicalize.*`’ intrinsic returns the platform-specific canonical encoding of a floating-point number. This canonicalization is useful for implementing certain numeric primitives such as frexp. The canonical encoding is defined by IEEE 754-2008 to be:

    2.1.8 canonical encoding: The preferred encoding of a floating-point
    representation in a format. Applied to declets, significands of finite
    numbers, infinities, and NaNs, especially in decimal formats.

This operation can also be considered equivalent to the IEEE 754-2008 conversion of a floating-point value to the same format. NaNs are handled according to section 6.2.

Examples of non-canonical encodings:

- x87 pseudo denormals, pseudo NaNs, pseudo Infinity, Unnormals. These are converted to a canonical representation per hardware-specific protocol.

- Many normal decimal floating-point numbers have non-canonical alternative encodings.

- Some machines, like GPUs or ARMv7 NEON, do not support subnormal values. These are treated as non-canonical encodings of zero and will be flushed to a zero of the same sign by this operation.

Note that per IEEE 754-2008 6.2, systems that support signaling NaNs with default exception handling must signal an invalid exception, and produce a quiet NaN result.

This function should always be implementable as multiplication by 1.0, provided that the compiler does not constant fold the operation. Likewise, division by 1.0 and `llvm.minnum(x, x)` are possible implementations. Addition with -0.0 is also sufficient provided that the rounding mode is not -Infinity.

`@llvm.canonicalize` must preserve the equality relation. That is:

- `(@llvm.canonicalize(x) == x)` is equivalent to `(x == x)`

- `(@llvm.canonicalize(x) == @llvm.canonicalize(y))` is equivalent to `(x == y)`

Additionally, the sign of zero must be conserved: `@llvm.canonicalize(-0.0) = -0.0` and `@llvm.canonicalize(+0.0) = +0.0`

The payload bits of a NaN must be conserved, with two exceptions. First, environments which use only a single canonical representation of NaN must perform said canonicalization. Second, SNaNs must be quieted per the usual methods.

The canonicalization operation may be optimized away if:

- The input is known to be canonical. For example, it was produced by a floating-point operation that is required by the standard to be canonical.

- The result is consumed only by (or fused with) other floating-point operations. That is, the bits of the floating-point value are not examined.

<a id="llvm-fmuladd-intrinsic"></a>

<a id="int-fmuladd"></a>

#### ‘`llvm.fmuladd.*`’ Intrinsic

<a id="id879"></a>

##### Syntax:

    declare float @llvm.fmuladd.f32(float %a, float %b, float %c)
    declare double @llvm.fmuladd.f64(double %a, double %b, double %c)

<a id="id880"></a>

##### Overview:

The ‘`llvm.fmuladd.*`’ intrinsic functions represent multiply-add expressions that can be fused if the code generator determines that (a) the target instruction set has support for a fused operation, and (b) that the fused operation is more efficient than the equivalent, separate pair of mul and add instructions.

<a id="id881"></a>

##### Arguments:

The ‘`llvm.fmuladd.*`’ intrinsics each take three arguments: two multiplicands, a and b, and an addend c.

<a id="id882"></a>

##### Semantics:

The expression:

    %0 = call float @llvm.fmuladd.f32(%a, %b, %c)

is equivalent to the expression a \* b + c, except that it is unspecified whether rounding will be performed between the multiplication and addition steps. Fusion is not guaranteed, even if the target platform supports it. If a fused multiply-add is required, the corresponding [llvm.fma](#int-fma) intrinsic function should be used instead. This never sets errno, just as ‘`llvm.fma.*`’.

<a id="id883"></a>

##### Examples:

    %r2 = call float @llvm.fmuladd.f32(float %a, float %b, float %c) ; yields float:r2 = (a * b) + c

<a id="hardware-loop-intrinsics"></a>

### Hardware-Loop Intrinsics

LLVM support several intrinsics to mark a loop as a hardware-loop. They are hints to the backend which are required to lower these intrinsics further to target specific instructions, or revert the hardware-loop to a normal loop if target specific restriction are not met and a hardware-loop can’t be generated.

These intrinsics may be modified in the future and are not intended to be used outside the backend. Thus, front-end and mid-level optimizations should not be generating these intrinsics.

<a id="llvm-set-loop-iterations-intrinsic"></a>

#### ‘`llvm.set.loop.iterations.*`’ Intrinsic

<a id="id884"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare void @llvm.set.loop.iterations.i32(i32)
    declare void @llvm.set.loop.iterations.i64(i64)

<a id="id885"></a>

##### Overview:

The ‘`llvm.set.loop.iterations.*`’ intrinsics are used to specify the hardware-loop trip count. They are placed in the loop preheader basic block and are marked as `IntrNoDuplicate` to avoid optimizers duplicating these instructions.

<a id="id886"></a>

##### Arguments:

The integer operand is the loop trip count of the hardware-loop, and thus not e.g., the loop back-edge taken count.

<a id="id887"></a>

##### Semantics:

The ‘`llvm.set.loop.iterations.*`’ intrinsics do not perform any arithmetic on their operand. It’s a hint to the backend that can use this to set up the hardware-loop count with a target-specific instruction, usually a move of this value to a special register or a hardware-loop instruction.

<a id="llvm-start-loop-iterations-intrinsic"></a>

#### ‘`llvm.start.loop.iterations.*`’ Intrinsic

<a id="id888"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.start.loop.iterations.i32(i32)
    declare i64 @llvm.start.loop.iterations.i64(i64)

<a id="id889"></a>

##### Overview:

The ‘`llvm.start.loop.iterations.*`’ intrinsics are similar to the ‘`llvm.set.loop.iterations.*`’ intrinsics, used to specify the hardware-loop trip count but also produce a value identical to the input that can be used as the input to the loop. They are placed in the loop preheader basic block and the output is expected to be the input to the phi for the induction variable of the loop, decremented by the ‘`llvm.loop.decrement.reg.*`’.

<a id="id890"></a>

##### Arguments:

The integer operand is the loop trip count of the hardware-loop, and thus not e.g., the loop back-edge taken count.

<a id="id891"></a>

##### Semantics:

The ‘`llvm.start.loop.iterations.*`’ intrinsics do not perform any arithmetic on their operand. It’s a hint to the backend that can use this to set up the hardware-loop count with a target-specific instruction, usually a move of this value to a special register or a hardware-loop instruction.

<a id="llvm-test-set-loop-iterations-intrinsic"></a>

#### ‘`llvm.test.set.loop.iterations.*`’ Intrinsic

<a id="id892"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i1 @llvm.test.set.loop.iterations.i32(i32)
    declare i1 @llvm.test.set.loop.iterations.i64(i64)

<a id="id893"></a>

##### Overview:

The ‘`llvm.test.set.loop.iterations.*`’ intrinsics are used to specify the the loop trip count, and also test that the given count is not zero, allowing it to control entry to a while-loop. They are placed in the loop preheader’s predecessor basic block, and are marked as `IntrNoDuplicate` to avoid optimizers duplicating these instructions.

<a id="id894"></a>

##### Arguments:

The integer operand is the loop trip count of the hardware-loop, and thus not e.g., the loop back-edge taken count.

<a id="id895"></a>

##### Semantics:

The ‘`llvm.test.set.loop.iterations.*`’ intrinsics do not perform any arithmetic on their operand. It’s a hint to the backend that can use this to set up the hardware-loop count with a target-specific instruction, usually a move of this value to a special register or a hardware-loop instruction. The result is the conditional value of whether the given count is not zero.

<a id="llvm-test-start-loop-iterations-intrinsic"></a>

#### ‘`llvm.test.start.loop.iterations.*`’ Intrinsic

<a id="id896"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare {i32, i1} @llvm.test.start.loop.iterations.i32(i32)
    declare {i64, i1} @llvm.test.start.loop.iterations.i64(i64)

<a id="id897"></a>

##### Overview:

The ‘`llvm.test.start.loop.iterations.*`’ intrinsics are similar to the ‘`llvm.test.set.loop.iterations.*`’ and ‘`llvm.start.loop.iterations.*`’ intrinsics, used to specify the hardware-loop trip count, but also produce a value identical to the input that can be used as the input to the loop. The second i1 output controls entry to a while-loop.

<a id="id898"></a>

##### Arguments:

The integer operand is the loop trip count of the hardware-loop, and thus not e.g., the loop back-edge taken count.

<a id="id899"></a>

##### Semantics:

The ‘`llvm.test.start.loop.iterations.*`’ intrinsics do not perform any arithmetic on their operand. It’s a hint to the backend that can use this to set up the hardware-loop count with a target-specific instruction, usually a move of this value to a special register or a hardware-loop instruction. The result is a pair of the input and a conditional value of whether the given count is not zero.

<a id="llvm-loop-decrement-reg-intrinsic"></a>

#### ‘`llvm.loop.decrement.reg.*`’ Intrinsic

<a id="id900"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.loop.decrement.reg.i32(i32, i32)
    declare i64 @llvm.loop.decrement.reg.i64(i64, i64)

<a id="id901"></a>

##### Overview:

The ‘`llvm.loop.decrement.reg.*`’ intrinsics are used to lower the loop iteration counter and return an updated value that will be used in the next loop test check.

<a id="id902"></a>

##### Arguments:

Both arguments must have identical integer types. The first operand is the loop iteration counter. The second operand is the maximum number of elements processed in an iteration.

<a id="id903"></a>

##### Semantics:

The ‘`llvm.loop.decrement.reg.*`’ intrinsics do an integer `SUB` of its two operands, which is not allowed to wrap. They return the remaining number of iterations still to be executed, and can be used together with a `PHI`, `ICMP` and `BR` to control the number of loop iterations executed. Any optimizations are allowed to treat it is a `SUB`, and it is supported by SCEV, so it’s the backends responsibility to handle cases where it may be optimized. These intrinsics are marked as `IntrNoDuplicate` to avoid optimizers duplicating these instructions.

<a id="llvm-loop-decrement-intrinsic"></a>

#### ‘`llvm.loop.decrement.*`’ Intrinsic

<a id="id904"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i1 @llvm.loop.decrement.i32(i32)
    declare i1 @llvm.loop.decrement.i64(i64)

<a id="id905"></a>

##### Overview:

The HardwareLoops pass allows the loop decrement value to be specified with an option. It defaults to a loop decrement value of 1, but it can be an unsigned integer value provided by this option. The ‘`llvm.loop.decrement.*`’ intrinsics decrement the loop iteration counter with this value, and return a false predicate if the loop should exit, and true otherwise. This is emitted if the loop counter is not updated via a `PHI` node, which can also be controlled with an option.

<a id="id906"></a>

##### Arguments:

The integer argument is the loop decrement value used to decrement the loop iteration counter.

<a id="id907"></a>

##### Semantics:

The ‘`llvm.loop.decrement.*`’ intrinsics do a `SUB` of the loop iteration counter with the given loop decrement value, and return false if the loop should exit, this `SUB` is not allowed to wrap. The result is a condition that is used by the conditional branch controlling the loop.
