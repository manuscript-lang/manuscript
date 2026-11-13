[Wiki](../index.md) › [LLVM LangRef](index.md)

# Intrinsics: floating point

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="saturating-floating-point-to-integer-conversions"></a>

### Saturating floating-point to integer conversions

The `fptoui` and `fptosi` instructions return a [poison value](constants.md#poisonvalues) if the rounded-towards-zero value is not representable by the result type. These intrinsics provide an alternative conversion, which will saturate towards the smallest and largest representable integer values instead.

<a id="llvm-fptoui-sat-intrinsic"></a>

#### ‘`llvm.fptoui.sat.*`’ Intrinsic

<a id="id1031"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.fptoui.sat` on any floating-point argument type and any integer result type, or vectors thereof. Not all targets may support all types, however.

    declare i32 @llvm.fptoui.sat.i32.f32(float %f)
    declare i19 @llvm.fptoui.sat.i19.f64(double %f)
    declare <4 x i100> @llvm.fptoui.sat.v4i100.v4f128(<4 x fp128> %f)

<a id="id1032"></a>

##### Overview:

This intrinsic converts the argument into an unsigned integer using saturating semantics.

<a id="id1033"></a>

##### Arguments:

The argument may be any floating-point or vector of floating-point type. The return value may be any integer or vector of integer type. The number of vector elements in argument and return must be the same.

<a id="id1034"></a>

##### Semantics:

The conversion to integer is performed subject to the following rules:

- If the argument is any NaN, zero is returned.

- If the argument is smaller than zero (this includes negative infinity), zero is returned.

- If the argument is larger than the largest representable unsigned integer of the result type (this includes positive infinity), the largest representable unsigned integer is returned.

- Otherwise, the result of rounding the argument towards zero is returned.

<a id="id1035"></a>

##### Example:

    %a = call i8 @llvm.fptoui.sat.i8.f32(float 123.875)            ; yields i8: 123
    %b = call i8 @llvm.fptoui.sat.i8.f32(float -5.75)              ; yields i8:   0
    %c = call i8 @llvm.fptoui.sat.i8.f32(float 377.0)              ; yields i8: 255
    %d = call i8 @llvm.fptoui.sat.i8.f32(float 0xFFF8000000000000) ; yields i8:   0

<a id="llvm-fptosi-sat-intrinsic"></a>

#### ‘`llvm.fptosi.sat.*`’ Intrinsic

<a id="id1036"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.fptosi.sat` on any floating-point argument type and any integer result type, or vectors thereof. Not all targets may support all types, however.

    declare i32 @llvm.fptosi.sat.i32.f32(float %f)
    declare i19 @llvm.fptosi.sat.i19.f64(double %f)
    declare <4 x i100> @llvm.fptosi.sat.v4i100.v4f128(<4 x fp128> %f)

<a id="id1037"></a>

##### Overview:

This intrinsic converts the argument into a signed integer using saturating semantics.

<a id="id1038"></a>

##### Arguments:

The argument may be any floating-point or vector of floating-point type. The return value may be any integer or vector of integer type. The number of vector elements in argument and return must be the same.

<a id="id1039"></a>

##### Semantics:

The conversion to integer is performed subject to the following rules:

- If the argument is any NaN, zero is returned.

- If the argument is smaller than the smallest representable signed integer of the result type (this includes negative infinity), the smallest representable signed integer is returned.

- If the argument is larger than the largest representable signed integer of the result type (this includes positive infinity), the largest representable signed integer is returned.

- Otherwise, the result of rounding the argument towards zero is returned.

<a id="id1040"></a>

##### Example:

    %a = call i8 @llvm.fptosi.sat.i8.f32(float 23.875)             ; yields i8:   23
    %b = call i8 @llvm.fptosi.sat.i8.f32(float -130.75)            ; yields i8: -128
    %c = call i8 @llvm.fptosi.sat.i8.f32(float 999.0)              ; yields i8:  127
    %d = call i8 @llvm.fptosi.sat.i8.f32(float 0xFFF8000000000000) ; yields i8:    0

<a id="floating-point-conversion-intrinsics"></a>

### Floating-Point Conversion Intrinsics

This class of intrinsics is designed for floating-point conversions that do not fall into other categories. For example conversions with specified rounding mode or mini-float conversions.

<a id="llvm-fptrunc-round-intrinsic"></a>

#### ‘`llvm.fptrunc.round`’ Intrinsic

<a id="id1041"></a>

##### Syntax:

    declare <ty2>
    @llvm.fptrunc.round(<type> <value>, metadata <rounding mode>)

<a id="id1042"></a>

##### Overview:

The ‘`llvm.fptrunc.round`’ intrinsic truncates [floating-point](type-system.md#t-floating) `value` to type `ty2` with a specified rounding mode.

<a id="id1043"></a>

##### Arguments:

The ‘`llvm.fptrunc.round`’ intrinsic takes a [floating-point](type-system.md#t-floating) value to cast and a [floating-point](type-system.md#t-floating) type to cast it to. This argument must be larger in size than the result.

The second argument specifies the rounding mode as described in the constrained intrinsics section. For this intrinsic, the “round.dynamic” mode is not supported.

<a id="id1044"></a>

##### Semantics:

The ‘`llvm.fptrunc.round`’ intrinsic casts a `value` from a larger [floating-point](type-system.md#t-floating) type to a smaller [floating-point](type-system.md#t-floating) type. This intrinsic is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv) *except* for the rounding mode. This intrinsic is not supported on all targets. Some targets may not support all rounding modes.

<a id="llvm-convert-to-arbitrary-fp-intrinsic"></a>

#### ‘`llvm.convert.to.arbitrary.fp`’ Intrinsic

<a id="id1045"></a>

##### Syntax:

    declare <iNxM> @llvm.convert.to.arbitrary.fp.<iNxM>.<fNxM>(
        <fNxM> <value>, metadata <interpretation>,
        metadata <rounding mode>, i1 <saturation>)

<a id="id1046"></a>

##### Overview:

The `llvm.convert.to.arbitrary.fp` intrinsic converts a native LLVM floating-point value to an arbitrary FP format, returning the result as an integer containing the arbitrary FP bits. This intrinsic is overloaded on both its return type and first argument.

<a id="id1047"></a>

##### Arguments:

`value`  
The native LLVM floating-point value to convert (e.g., `half`, `float`, `double`).

`interpretation`  
A metadata string describing the target arbitrary FP format. Supported format names include:

- FP8 formats: `"Float8E5M2"`, `"Float8E5M2FNUZ"`, `"Float8E4M3"`, `"Float8E4M3FN"`, `"Float8E4M3FNUZ"`, `"Float8E4M3B11FNUZ"`, `"Float8E3M4"`, `"Float8E8M0FNU"`

- FP6 formats: `"Float6E3M2FN"`, `"Float6E2M3FN"`

- FP4 formats: `"Float4E2M1FN"`

The bit width of the integer return type must equal the bit width of the selected format, for example `i8` for an FP8 format, `i6` for an FP6 format, and `i4` for an FP4 format. For vector operands this applies to the integer element type.

`rounding mode`  
A metadata string specifying the rounding mode. The permitted strings match those accepted by `llvm.fptrunc.round` (for example, `"round.tonearest"` or `"round.towardzero"`).

The rounding mode is only consulted when `value` is not exactly representable in the target format. If the value is exactly representable, all rounding modes produce the same result.

`saturation`  
A compile-time constant boolean value (`i1`). This parameter controls how overflow is handled when values exceed the representable finite range of the target format:

- When `true`: overflowing values are clamped to the minimum or maximum representable finite value (saturating to the largest negative finite value or largest positive finite value).

- When `false`: overflowing values are converted to infinity (preserving sign of the original value) if the target format supports infinity, or return a poison value if infinity is not supported by the target format.

This parameter must be an immediate constant.

<a id="id1048"></a>

##### Semantics:

The intrinsic converts the native LLVM floating-point value to the arbitrary FP format specified by `interpretation`, applying the requested rounding mode and saturation behavior. The conversion is performed in two steps: first, the value is rounded according to the specified rounding mode to fit the target format’s precision; then, if the rounded result exceeds the target format’s representable range, saturation is applied according to the `saturation` parameter. The result is returned as an integer whose bit width equals the format’s bit width (`i8` for FP8, `i6` for FP6, `i4` for FP4) containing the encoded arbitrary FP bits.

**Handling of special values:**

- **NaN**: NaN values follow LLVM’s standard [NaN rules](high-level-structure.md#floatnan). When the target format supports NaN, the NaN representation is preserved (quiet NaNs remain quiet, signaling NaNs remain signaling). The exact NaN payload may be truncated or extended to fit the target format’s payload size. If the target format does not support NaN, the intrinsic returns a poison value.

- **Infinity and Overflow**: If the input is +/-Inf or a finite value that exceeds the representable range:

  - When `saturation` is `false` and the target format supports infinity, the result is +/-Inf (preserving the sign).

  - When `saturation` is `false` and the target format does not support infinity (e.g., formats with “FN” suffix), the intrinsic returns a poison value.

  - When `saturation` is `true`, the value is clamped to the maximum/minimum representable finite value.

For FP6/FP4 interpretations, producers are expected to use `saturation` = `true`; using `saturation` = `false` and generating NaN/Inf/overflowing values results in a poison value.

<a id="id1049"></a>

##### Example:

    ; Convert half to FP8 E4M3 format
    %fp8bits = call i8 @llvm.convert.to.arbitrary.fp.i8.f16(
        half %value, metadata !"Float8E4M3",
        metadata !"round.tonearest", i1 false)

    ; Convert vector of float to FP8 E5M2 with saturation
    %vec_fp8 = call <4 x i8> @llvm.convert.to.arbitrary.fp.v4i8.v4f32(
        <4 x float> %values, metadata !"Float8E5M2",
        metadata !"round.towardzero", i1 true)

<a id="llvm-convert-from-arbitrary-fp-intrinsic"></a>

#### ‘`llvm.convert.from.arbitrary.fp`’ Intrinsic

<a id="id1050"></a>

##### Syntax:

    declare <fNxM> @llvm.convert.from.arbitrary.fp.<fNxM>.<iNxM>(
        <iNxM> <value>, metadata <interpretation>)

<a id="id1051"></a>

##### Overview:

The `llvm.convert.from.arbitrary.fp` intrinsic converts an integer containing arbitrary FP bits to a native LLVM floating-point value. This intrinsic is overloaded on both its return type and first argument.

<a id="id1052"></a>

##### Arguments:

`value`  
An integer value containing the arbitrary FP bits. Its bit width must equal the bit width of the format selected by `interpretation`, for example `i8` for an FP8 format, `i6` for an FP6 format, and `i4` for an FP4 format. For vector operands this applies to the integer element type.

`interpretation`  
A metadata string describing the source arbitrary FP format. Supported format names include:

- FP8 formats: `"Float8E5M2"`, `"Float8E5M2FNUZ"`, `"Float8E4M3"`, `"Float8E4M3FN"`, `"Float8E4M3FNUZ"`, `"Float8E4M3B11FNUZ"`, `"Float8E3M4"`, `"Float8E8M0FNU"`

- FP6 formats: `"Float6E3M2FN"`, `"Float6E2M3FN"`

- FP4 formats: `"Float4E2M1FN"`

<a id="id1053"></a>

##### Semantics:

The intrinsic interprets the integer value as arbitrary FP bits according to `interpretation`, then converts to the native LLVM floating-point result type.

Conversions from arbitrary FP formats to native LLVM floating-point types are widening conversions (e.g., FP8 to FP16 or FP32), which are exact and require no rounding. Normal finite values are converted exactly. NaN values follow LLVM’s standard [NaN rules](high-level-structure.md#floatnan); the NaN representation is preserved (quiet NaNs remain quiet, signaling NaNs remain signaling), and the NaN payload may be truncated or extended to fit the target format’s payload size. Infinity values are preserved as infinity. If a value exceeds the representable range of the target type (for example, converting `Float8E8M0FNU` with large exponents to `half`), the result is converted to infinity with the appropriate sign.

<a id="id1054"></a>

##### Example:

    ; Convert FP8 E4M3 bits to half
    %half_val = call half @llvm.convert.from.arbitrary.fp.f16.i8(
        i8 %fp8bits, metadata !"Float8E4M3")

    ; Convert vector of FP8 E5M2 bits to float
    %vec_float = call <4 x float> @llvm.convert.from.arbitrary.fp.v4f32.v4i8(
        <4 x i8> %fp8_values, metadata !"Float8E5M2")

<a id="constrained-floating-point-intrinsics"></a>

<a id="constrainedfp"></a>

### Constrained Floating-Point Intrinsics

These intrinsics are used to provide special handling of floating-point operations when specific rounding mode or floating-point exception behavior is required. By default, LLVM optimization passes assume that the rounding mode is round-to-nearest and that floating-point exceptions will not be monitored. Constrained FP intrinsics are used to support non-default rounding modes and accurately preserve exception behavior without compromising LLVM’s ability to optimize FP code when the default behavior is used.

If any FP operation in a function is constrained then they all must be constrained. This is required for correct LLVM IR. Optimizations that move code around can create miscompiles if mixing of constrained and normal operations is done. The correct way to mix constrained and less constrained operations is to use the rounding mode and exception handling metadata to mark constrained intrinsics as having LLVM’s default behavior.

Each of these intrinsics corresponds to a normal floating-point operation. The data arguments and the return value are the same as the corresponding FP operation.

The rounding mode argument is a metadata string specifying what assumptions, if any, the optimizer can make when transforming constant values. Some constrained FP intrinsics omit this argument. If required by the intrinsic, this argument must be one of the following strings:

    "round.dynamic"
    "round.tonearest"
    "round.downward"
    "round.upward"
    "round.towardzero"
    "round.tonearestaway"

If this argument is “round.dynamic” optimization passes must assume that the rounding mode is unknown and may change at runtime. No transformations that depend on rounding mode may be performed in this case.

The other possible values for the rounding mode argument correspond to the similarly named IEEE rounding modes. If the argument is any of these values optimization passes may perform transformations as long as they are consistent with the specified rounding mode.

For example, ‘x-0’-\>’x’ is not a valid transformation if the rounding mode is “round.downward” or “round.dynamic” because if the value of ‘x’ is +0 then ‘x-0’ should evaluate to ‘-0’ when rounding downward. However, this transformation is legal for all other rounding modes.

For values other than “round.dynamic” optimization passes may assume that the actual runtime rounding mode (as defined in a target-specific manner) matches the specified rounding mode, but this is not guaranteed. Using a specific non-dynamic rounding mode which does not match the actual rounding mode at runtime results in undefined behavior.

The exception behavior argument is a metadata string describing the floating point exception semantics that required for the intrinsic. This argument must be one of the following strings:

    "fpexcept.ignore"
    "fpexcept.maytrap"
    "fpexcept.strict"

If this argument is “fpexcept.ignore” optimization passes may assume that the exception status flags will not be read and that floating-point exceptions will be masked. This allows transformations to be performed that may change the exception semantics of the original code. For example, FP operations may be speculatively executed in this case whereas they must not be for either of the other possible values of this argument.

If the exception behavior argument is “fpexcept.maytrap” optimization passes must avoid transformations that may raise exceptions that would not have been raised by the original code (such as speculatively executing FP operations), but passes are not required to preserve all exceptions that are implied by the original code. For example, exceptions may be potentially hidden by constant folding.

If the exception behavior argument is “fpexcept.strict” all transformations must strictly preserve the floating-point exception semantics of the original code. Any FP exception that would have been raised by the original code must be raised by the transformed code, and the transformed code must not raise any FP exceptions that would not have been raised by the original code. This is the exception behavior argument that will be used if the code being compiled reads the FP exception status flags, but this mode can also be used with code that unmasks FP exceptions.

The number and order of floating-point exceptions is NOT guaranteed. For example, a series of FP operations that each may raise exceptions may be vectorized into a single instruction that raises each unique exception a single time.

Proper [function attributes](high-level-structure.md#fnattrs) usage is required for the constrained intrinsics to function correctly.

All function *calls* done in a function that uses constrained floating point intrinsics must have the `strictfp` attribute either on the calling instruction or on the declaration or definition of the function being called.

All function *definitions* that use constrained floating point intrinsics must have the `strictfp` attribute.

<a id="llvm-experimental-constrained-fadd-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fadd`’ Intrinsic

<a id="id1595"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.fadd(<type> <op1>, <type> <op2>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1596"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fadd`’ intrinsic returns the sum of its two arguments.

<a id="id1597"></a>

##### Arguments:

The first two arguments to the ‘`llvm.experimental.constrained.fadd`’ intrinsic must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1598"></a>

##### Semantics:

The value produced is the floating-point sum of the two value arguments and has the same type as the arguments.

<a id="llvm-experimental-constrained-fsub-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fsub`’ Intrinsic

<a id="id1599"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.fsub(<type> <op1>, <type> <op2>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1600"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fsub`’ intrinsic returns the difference of its two arguments.

<a id="id1601"></a>

##### Arguments:

The first two arguments to the ‘`llvm.experimental.constrained.fsub`’ intrinsic must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1602"></a>

##### Semantics:

The value produced is the floating-point difference of the two value arguments and has the same type as the arguments.

<a id="llvm-experimental-constrained-fmul-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fmul`’ Intrinsic

<a id="id1603"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.fmul(<type> <op1>, <type> <op2>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1604"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fmul`’ intrinsic returns the product of its two arguments.

<a id="id1605"></a>

##### Arguments:

The first two arguments to the ‘`llvm.experimental.constrained.fmul`’ intrinsic must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1606"></a>

##### Semantics:

The value produced is the floating-point product of the two value arguments and has the same type as the arguments.

<a id="llvm-experimental-constrained-fdiv-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fdiv`’ Intrinsic

<a id="id1607"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.fdiv(<type> <op1>, <type> <op2>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1608"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fdiv`’ intrinsic returns the quotient of its two arguments.

<a id="id1609"></a>

##### Arguments:

The first two arguments to the ‘`llvm.experimental.constrained.fdiv`’ intrinsic must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1610"></a>

##### Semantics:

The value produced is the floating-point quotient of the two value arguments and has the same type as the arguments.

<a id="llvm-experimental-constrained-frem-intrinsic"></a>

#### ‘`llvm.experimental.constrained.frem`’ Intrinsic

<a id="id1611"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.frem(<type> <op1>, <type> <op2>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1612"></a>

##### Overview:

The ‘`llvm.experimental.constrained.frem`’ intrinsic returns the remainder from the division of its two arguments.

<a id="id1613"></a>

##### Arguments:

The first two arguments to the ‘`llvm.experimental.constrained.frem`’ intrinsic must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

The third and fourth arguments specify the rounding mode and exception behavior as described above. The rounding mode argument has no effect, since the result of frem is never rounded, but the argument is included for consistency with the other constrained floating-point intrinsics.

<a id="id1614"></a>

##### Semantics:

The value produced is the floating-point remainder from the division of the two value arguments and has the same type as the arguments. The remainder has the same sign as the dividend.

<a id="llvm-experimental-constrained-fma-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fma`’ Intrinsic

<a id="id1615"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.fma(<type> <op1>, <type> <op2>, <type> <op3>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1616"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fma`’ intrinsic returns the result of a fused-multiply-add operation on its arguments.

<a id="id1617"></a>

##### Arguments:

The first three arguments to the ‘`llvm.experimental.constrained.fma`’ intrinsic must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. All arguments must have identical types.

The fourth and fifth arguments specify the rounding mode and exception behavior as described above.

<a id="id1618"></a>

##### Semantics:

The result produced is the product of the first two arguments added to the third argument computed with infinite precision, and then rounded to the target precision.

<a id="llvm-experimental-constrained-fptoui-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fptoui`’ Intrinsic

<a id="id1619"></a>

##### Syntax:

    declare <ty2>
    @llvm.experimental.constrained.fptoui(<type> <value>,
                                        metadata <exception behavior>)

<a id="id1620"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fptoui`’ intrinsic converts a floating-point `value` to its unsigned integer equivalent of type `ty2`.

<a id="id1621"></a>

##### Arguments:

The first argument to the ‘`llvm.experimental.constrained.fptoui`’ intrinsic must be [floating point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating point values.

The second argument specifies the exception behavior as described above.

<a id="id1622"></a>

##### Semantics:

The result produced is an unsigned integer converted from the floating point argument. The value is truncated, so it is rounded towards zero.

<a id="llvm-experimental-constrained-fptosi-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fptosi`’ Intrinsic

<a id="id1623"></a>

##### Syntax:

    declare <ty2>
    @llvm.experimental.constrained.fptosi(<type> <value>,
                                        metadata <exception behavior>)

<a id="id1624"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fptosi`’ intrinsic converts [floating-point](type-system.md#t-floating) `value` to type `ty2`.

<a id="id1625"></a>

##### Arguments:

The first argument to the ‘`llvm.experimental.constrained.fptosi`’ intrinsic must be [floating point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating point values.

The second argument specifies the exception behavior as described above.

<a id="id1626"></a>

##### Semantics:

The result produced is a signed integer converted from the floating point argument. The value is truncated, so it is rounded towards zero.

<a id="llvm-experimental-constrained-uitofp-intrinsic"></a>

#### ‘`llvm.experimental.constrained.uitofp`’ Intrinsic

<a id="id1627"></a>

##### Syntax:

    declare <ty2>
    @llvm.experimental.constrained.uitofp(<type> <value>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1628"></a>

##### Overview:

The ‘`llvm.experimental.constrained.uitofp`’ intrinsic converts an unsigned integer `value` to a floating-point of type `ty2`.

<a id="id1629"></a>

##### Arguments:

The first argument to the ‘`llvm.experimental.constrained.uitofp`’ intrinsic must be an [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1630"></a>

##### Semantics:

An inexact floating-point exception will be raised if rounding is required. Any result produced is a floating point value converted from the input integer argument.

<a id="llvm-experimental-constrained-sitofp-intrinsic"></a>

#### ‘`llvm.experimental.constrained.sitofp`’ Intrinsic

<a id="id1631"></a>

##### Syntax:

    declare <ty2>
    @llvm.experimental.constrained.sitofp(<type> <value>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1632"></a>

##### Overview:

The ‘`llvm.experimental.constrained.sitofp`’ intrinsic converts a signed integer `value` to a floating-point of type `ty2`.

<a id="id1633"></a>

##### Arguments:

The first argument to the ‘`llvm.experimental.constrained.sitofp`’ intrinsic must be an [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1634"></a>

##### Semantics:

An inexact floating-point exception will be raised if rounding is required. Any result produced is a floating point value converted from the input integer argument.

<a id="llvm-experimental-constrained-fptrunc-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fptrunc`’ Intrinsic

<a id="id1635"></a>

##### Syntax:

    declare <ty2>
    @llvm.experimental.constrained.fptrunc(<type> <value>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1636"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fptrunc`’ intrinsic truncates `value` to type `ty2`.

<a id="id1637"></a>

##### Arguments:

The first argument to the ‘`llvm.experimental.constrained.fptrunc`’ intrinsic must be [floating point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating point values. This argument must be larger in size than the result.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1638"></a>

##### Semantics:

The result produced is a floating point value truncated to be smaller in size than the argument.

<a id="llvm-experimental-constrained-fpext-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fpext`’ Intrinsic

<a id="id1639"></a>

##### Syntax:

    declare <ty2>
    @llvm.experimental.constrained.fpext(<type> <value>,
                                        metadata <exception behavior>)

<a id="id1640"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fpext`’ intrinsic extends a floating-point `value` to a larger floating-point value.

<a id="id1641"></a>

##### Arguments:

The first argument to the ‘`llvm.experimental.constrained.fpext`’ intrinsic must be [floating point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating point values. This argument must be smaller in size than the result.

The second argument specifies the exception behavior as described above.

<a id="id1642"></a>

##### Semantics:

The result produced is a floating point value extended to be larger in size than the argument. All restrictions that apply to the fpext instruction also apply to this intrinsic.

<a id="llvm-experimental-constrained-fcmp-and-llvm-experimental-constrained-fcmps-intrinsics"></a>

#### ‘`llvm.experimental.constrained.fcmp`’ and ‘`llvm.experimental.constrained.fcmps`’ Intrinsics

<a id="id1643"></a>

##### Syntax:

    declare <ty2>
    @llvm.experimental.constrained.fcmp(<type> <op1>, <type> <op2>,
                                        metadata <condition code>,
                                        metadata <exception behavior>)
    declare <ty2>
    @llvm.experimental.constrained.fcmps(<type> <op1>, <type> <op2>,
                                         metadata <condition code>,
                                         metadata <exception behavior>)

<a id="id1644"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fcmp`’ and ‘`llvm.experimental.constrained.fcmps`’ intrinsics return a boolean value or vector of boolean values based on comparison of its arguments.

If the arguments are floating-point scalars, then the result type is a boolean ([i1](type-system.md#t-integer)).

If the arguments are floating-point vectors, then the result type is a vector of boolean with the same number of elements as the arguments being compared.

The ‘`llvm.experimental.constrained.fcmp`’ intrinsic performs a quiet comparison operation while the ‘`llvm.experimental.constrained.fcmps`’ intrinsic performs a signaling comparison operation.

<a id="id1645"></a>

##### Arguments:

The first two arguments to the ‘`llvm.experimental.constrained.fcmp`’ and ‘`llvm.experimental.constrained.fcmps`’ intrinsics must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

The third argument is the condition code indicating the kind of comparison to perform. It must be a metadata string with one of the following values:

- “`oeq`”: ordered and equal

- “`ogt`”: ordered and greater than

- “`oge`”: ordered and greater than or equal

- “`olt`”: ordered and less than

- “`ole`”: ordered and less than or equal

- “`one`”: ordered and not equal

- “`ord`”: ordered (no nans)

- “`ueq`”: unordered or equal

- “`ugt`”: unordered or greater than

- “`uge`”: unordered or greater than or equal

- “`ult`”: unordered or less than

- “`ule`”: unordered or less than or equal

- “`une`”: unordered or not equal

- “`uno`”: unordered (either nans)

*Ordered* means that neither argument is a NAN while *unordered* means that either argument may be a NAN.

The fourth argument specifies the exception behavior as described above.

<a id="id1646"></a>

##### Semantics:

`op1` and `op2` are compared according to the condition code given as the third argument. If the arguments are vectors, then the vectors are compared element by element. Each comparison performed always yields an [i1](type-system.md#t-integer) result, as follows:

- “`oeq`”: yields `true` if both arguments are not a NAN and `op1` is equal to `op2`.

- “`ogt`”: yields `true` if both arguments are not a NAN and `op1` is greater than `op2`.

- “`oge`”: yields `true` if both arguments are not a NAN and `op1` is greater than or equal to `op2`.

- “`olt`”: yields `true` if both arguments are not a NAN and `op1` is less than `op2`.

- “`ole`”: yields `true` if both arguments are not a NAN and `op1` is less than or equal to `op2`.

- “`one`”: yields `true` if both arguments are not a NAN and `op1` is not equal to `op2`.

- “`ord`”: yields `true` if both arguments are not a NAN.

- “`ueq`”: yields `true` if either argument is a NAN or `op1` is equal to `op2`.

- “`ugt`”: yields `true` if either argument is a NAN or `op1` is greater than `op2`.

- “`uge`”: yields `true` if either argument is a NAN or `op1` is greater than or equal to `op2`.

- “`ult`”: yields `true` if either argument is a NAN or `op1` is less than `op2`.

- “`ule`”: yields `true` if either argument is a NAN or `op1` is less than or equal to `op2`.

- “`une`”: yields `true` if either argument is a NAN or `op1` is not equal to `op2`.

- “`uno`”: yields `true` if either argument is a NAN.

The quiet comparison operation performed by ‘`llvm.experimental.constrained.fcmp`’ will only raise an exception if either argument is a SNAN. The signaling comparison operation performed by ‘`llvm.experimental.constrained.fcmps`’ will raise an exception if either argument is a NAN (QNAN or SNAN). Such an exception does not preclude a result being produced (e.g., exception might only set a flag), therefore the distinction between ordered and unordered comparisons is also relevant for the ‘`llvm.experimental.constrained.fcmps`’ intrinsic.

<a id="llvm-experimental-constrained-fmuladd-intrinsic"></a>

#### ‘`llvm.experimental.constrained.fmuladd`’ Intrinsic

<a id="id1647"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.fmuladd(<type> <op1>, <type> <op2>,
                                           <type> <op3>,
                                           metadata <rounding mode>,
                                           metadata <exception behavior>)

<a id="id1648"></a>

##### Overview:

The ‘`llvm.experimental.constrained.fmuladd`’ intrinsic represents multiply-add expressions that can be fused if the code generator determines that (a) the target instruction set has support for a fused operation, and (b) that the fused operation is more efficient than the equivalent, separate pair of mul and add instructions.

<a id="id1649"></a>

##### Arguments:

The first three arguments to the ‘`llvm.experimental.constrained.fmuladd`’ intrinsic must be floating-point or vector of floating-point values. All three arguments must have identical types.

The fourth and fifth arguments specify the rounding mode and exception behavior as described above.

<a id="id1650"></a>

##### Semantics:

The expression:

    %0 = call float @llvm.experimental.constrained.fmuladd.f32(%a, %b, %c,
                                                               metadata <rounding mode>,
                                                               metadata <exception behavior>)

is equivalent to the expression:

    %0 = call float @llvm.experimental.constrained.fmul.f32(%a, %b,
                                                            metadata <rounding mode>,
                                                            metadata <exception behavior>)
    %1 = call float @llvm.experimental.constrained.fadd.f32(%0, %c,
                                                            metadata <rounding mode>,
                                                            metadata <exception behavior>)

except that it is unspecified whether rounding will be performed between the multiplication and addition steps. Fusion is not guaranteed, even if the target platform supports it. If a fused multiply-add is required, the corresponding [llvm.experimental.constrained.fma](intrinsics-libc-and-arithmetic.md#int-fma) intrinsic function should be used instead. This never sets errno, just as ‘`llvm.experimental.constrained.fma.*`’.

<a id="constrained-libm-equivalent-intrinsics"></a>

### Constrained libm-equivalent Intrinsics

In addition to the basic floating-point operations for which constrained intrinsics are described above, there are constrained versions of various operations which provide equivalent behavior to a corresponding libm function. These intrinsics allow the precise behavior of these operations with respect to rounding mode and exception behavior to be controlled.

As with the basic constrained floating-point intrinsics, the rounding mode and exception behavior arguments only control the behavior of the optimizer. They do not change the runtime floating-point environment.

<a id="llvm-experimental-constrained-sqrt-intrinsic"></a>

#### ‘`llvm.experimental.constrained.sqrt`’ Intrinsic

<a id="id1651"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.sqrt(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1652"></a>

##### Overview:

The ‘`llvm.experimental.constrained.sqrt`’ intrinsic returns the square root of the specified value, returning the same value as the libm ‘`sqrt`’ functions would, but without setting `errno`.

<a id="id1653"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1654"></a>

##### Semantics:

This function returns the nonnegative square root of the specified value. If the value is less than negative zero, a floating-point exception occurs and the return value is architecture specific.

<a id="llvm-experimental-constrained-pow-intrinsic"></a>

#### ‘`llvm.experimental.constrained.pow`’ Intrinsic

<a id="id1655"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.pow(<type> <op1>, <type> <op2>,
                                       metadata <rounding mode>,
                                       metadata <exception behavior>)

<a id="id1656"></a>

##### Overview:

The ‘`llvm.experimental.constrained.pow`’ intrinsic returns the first argument raised to the (positive or negative) power specified by the second argument.

<a id="id1657"></a>

##### Arguments:

The first two arguments and the return value are floating-point numbers of the same type. The second argument specifies the power to which the first argument should be raised.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1658"></a>

##### Semantics:

This function returns the first value raised to the second power, returning the same values as the libm `pow` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-powi-intrinsic"></a>

#### ‘`llvm.experimental.constrained.powi`’ Intrinsic

<a id="id1659"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.powi(<type> <op1>, i32 <op2>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1660"></a>

##### Overview:

The ‘`llvm.experimental.constrained.powi`’ intrinsic returns the first argument raised to the (positive or negative) power specified by the second argument. The order of evaluation of multiplications is not defined. When a vector of floating-point type is used, the second argument remains a scalar integer value.

<a id="id1661"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type. The second argument is a 32-bit signed integer specifying the power to which the first argument should be raised.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1662"></a>

##### Semantics:

This function returns the first value raised to the second power with an unspecified sequence of rounding operations.

<a id="llvm-experimental-constrained-ldexp-intrinsic"></a>

#### ‘`llvm.experimental.constrained.ldexp`’ Intrinsic

<a id="id1663"></a>

##### Syntax:

    declare <type0>
    @llvm.experimental.constrained.ldexp(<type0> <op1>, <type1> <op2>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1664"></a>

##### Overview:

The ‘`llvm.experimental.constrained.ldexp`’ performs the ldexp function.

<a id="id1665"></a>

##### Arguments:

The first argument and the return value are [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values of the same type. The second argument is an integer with the same number of elements.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1666"></a>

##### Semantics:

This function multiplies the first argument by 2 raised to the second argument’s power. If the first argument is NaN or infinite, the same value is returned. If the result underflows a zero with the same sign is returned. If the result overflows, the result is an infinity with the same sign.

<a id="llvm-experimental-constrained-sin-intrinsic"></a>

#### ‘`llvm.experimental.constrained.sin`’ Intrinsic

<a id="id1667"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.sin(<type> <op1>,
                                       metadata <rounding mode>,
                                       metadata <exception behavior>)

<a id="id1668"></a>

##### Overview:

The ‘`llvm.experimental.constrained.sin`’ intrinsic returns the sine of the first argument.

<a id="id1669"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1670"></a>

##### Semantics:

This function returns the sine of the specified argument, returning the same values as the libm `sin` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-cos-intrinsic"></a>

#### ‘`llvm.experimental.constrained.cos`’ Intrinsic

<a id="id1671"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.cos(<type> <op1>,
                                       metadata <rounding mode>,
                                       metadata <exception behavior>)

<a id="id1672"></a>

##### Overview:

The ‘`llvm.experimental.constrained.cos`’ intrinsic returns the cosine of the first argument.

<a id="id1673"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1674"></a>

##### Semantics:

This function returns the cosine of the specified argument, returning the same values as the libm `cos` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-tan-intrinsic"></a>

#### ‘`llvm.experimental.constrained.tan`’ Intrinsic

<a id="id1675"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.tan(<type> <op1>,
                                       metadata <rounding mode>,
                                       metadata <exception behavior>)

<a id="id1676"></a>

##### Overview:

The ‘`llvm.experimental.constrained.tan`’ intrinsic returns the tangent of the first argument.

<a id="id1677"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1678"></a>

##### Semantics:

This function returns the tangent of the specified argument, returning the same values as the libm `tan` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-asin-intrinsic"></a>

#### ‘`llvm.experimental.constrained.asin`’ Intrinsic

<a id="id1679"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.asin(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1680"></a>

##### Overview:

The ‘`llvm.experimental.constrained.asin`’ intrinsic returns the arcsine of the first operand.

<a id="id1681"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1682"></a>

##### Semantics:

This function returns the arcsine of the specified operand, returning the same values as the libm `asin` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-acos-intrinsic"></a>

#### ‘`llvm.experimental.constrained.acos`’ Intrinsic

<a id="id1683"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.acos(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1684"></a>

##### Overview:

The ‘`llvm.experimental.constrained.acos`’ intrinsic returns the arccosine of the first operand.

<a id="id1685"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1686"></a>

##### Semantics:

This function returns the arccosine of the specified operand, returning the same values as the libm `acos` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-atan-intrinsic"></a>

#### ‘`llvm.experimental.constrained.atan`’ Intrinsic

<a id="id1687"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.atan(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1688"></a>

##### Overview:

The ‘`llvm.experimental.constrained.atan`’ intrinsic returns the arctangent of the first operand.

<a id="id1689"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1690"></a>

##### Semantics:

This function returns the arctangent of the specified operand, returning the same values as the libm `atan` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-atan2-intrinsic"></a>

#### ‘`llvm.experimental.constrained.atan2`’ Intrinsic

<a id="id1691"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.atan2(<type> <op1>,
                                         <type> <op2>,
                                         metadata <rounding mode>,
                                         metadata <exception behavior>)

<a id="id1692"></a>

##### Overview:

The ‘`llvm.experimental.constrained.atan2`’ intrinsic returns the arctangent of `<op1>` divided by `<op2>` accounting for the quadrant.

<a id="id1693"></a>

##### Arguments:

The first two arguments and the return value are floating-point numbers of the same type.

The third and fourth arguments specify the rounding mode and exception behavior as described above.

<a id="id1694"></a>

##### Semantics:

This function returns the quadrant-specific arctangent using the specified operands, returning the same values as the libm `atan2` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-sinh-intrinsic"></a>

#### ‘`llvm.experimental.constrained.sinh`’ Intrinsic

<a id="id1695"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.sinh(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1696"></a>

##### Overview:

The ‘`llvm.experimental.constrained.sinh`’ intrinsic returns the hyperbolic sine of the first operand.

<a id="id1697"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1698"></a>

##### Semantics:

This function returns the hyperbolic sine of the specified operand, returning the same values as the libm `sinh` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-cosh-intrinsic"></a>

#### ‘`llvm.experimental.constrained.cosh`’ Intrinsic

<a id="id1699"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.cosh(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1700"></a>

##### Overview:

The ‘`llvm.experimental.constrained.cosh`’ intrinsic returns the hyperbolic cosine of the first operand.

<a id="id1701"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1702"></a>

##### Semantics:

This function returns the hyperbolic cosine of the specified operand, returning the same values as the libm `cosh` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-tanh-intrinsic"></a>

#### ‘`llvm.experimental.constrained.tanh`’ Intrinsic

<a id="id1703"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.tanh(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1704"></a>

##### Overview:

The ‘`llvm.experimental.constrained.tanh`’ intrinsic returns the hyperbolic tangent of the first operand.

<a id="id1705"></a>

##### Arguments:

The first argument and the return type are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1706"></a>

##### Semantics:

This function returns the hyperbolic tangent of the specified operand, returning the same values as the libm `tanh` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-exp-intrinsic"></a>

#### ‘`llvm.experimental.constrained.exp`’ Intrinsic

<a id="id1707"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.exp(<type> <op1>,
                                       metadata <rounding mode>,
                                       metadata <exception behavior>)

<a id="id1708"></a>

##### Overview:

The ‘`llvm.experimental.constrained.exp`’ intrinsic computes the base-e exponential of the specified value.

<a id="id1709"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1710"></a>

##### Semantics:

This function returns the same values as the libm `exp` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-exp2-intrinsic"></a>

#### ‘`llvm.experimental.constrained.exp2`’ Intrinsic

<a id="id1711"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.exp2(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1712"></a>

##### Overview:

The ‘`llvm.experimental.constrained.exp2`’ intrinsic computes the base-2 exponential of the specified value.

<a id="id1713"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1714"></a>

##### Semantics:

This function returns the same values as the libm `exp2` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-log-intrinsic"></a>

#### ‘`llvm.experimental.constrained.log`’ Intrinsic

<a id="id1715"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.log(<type> <op1>,
                                       metadata <rounding mode>,
                                       metadata <exception behavior>)

<a id="id1716"></a>

##### Overview:

The ‘`llvm.experimental.constrained.log`’ intrinsic computes the base-e logarithm of the specified value.

<a id="id1717"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1718"></a>

##### Semantics:

This function returns the same values as the libm `log` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-log10-intrinsic"></a>

#### ‘`llvm.experimental.constrained.log10`’ Intrinsic

<a id="id1719"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.log10(<type> <op1>,
                                         metadata <rounding mode>,
                                         metadata <exception behavior>)

<a id="id1720"></a>

##### Overview:

The ‘`llvm.experimental.constrained.log10`’ intrinsic computes the base-10 logarithm of the specified value.

<a id="id1721"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1722"></a>

##### Semantics:

This function returns the same values as the libm `log10` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-log2-intrinsic"></a>

#### ‘`llvm.experimental.constrained.log2`’ Intrinsic

<a id="id1723"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.log2(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1724"></a>

##### Overview:

The ‘`llvm.experimental.constrained.log2`’ intrinsic computes the base-2 logarithm of the specified value.

<a id="id1725"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1726"></a>

##### Semantics:

This function returns the same values as the libm `log2` functions would, and handles error conditions in the same way.

<a id="llvm-experimental-constrained-rint-intrinsic"></a>

#### ‘`llvm.experimental.constrained.rint`’ Intrinsic

<a id="id1727"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.rint(<type> <op1>,
                                        metadata <rounding mode>,
                                        metadata <exception behavior>)

<a id="id1728"></a>

##### Overview:

The ‘`llvm.experimental.constrained.rint`’ intrinsic returns the first argument rounded to the nearest integer. It may raise an inexact floating-point exception if the argument is not an integer.

<a id="id1729"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1730"></a>

##### Semantics:

This function returns the same values as the libm `rint` functions would, and handles error conditions in the same way. The rounding mode is described, not determined, by the rounding mode argument. The actual rounding mode is determined by the runtime floating-point environment. The rounding mode argument is only intended as information to the compiler.

<a id="llvm-experimental-constrained-lrint-intrinsic"></a>

#### ‘`llvm.experimental.constrained.lrint`’ Intrinsic

<a id="id1731"></a>

##### Syntax:

    declare <inttype>
    @llvm.experimental.constrained.lrint(<fptype> <op1>,
                                         metadata <rounding mode>,
                                         metadata <exception behavior>)

<a id="id1732"></a>

##### Overview:

The ‘`llvm.experimental.constrained.lrint`’ intrinsic returns the first argument rounded to the nearest integer. An inexact floating-point exception will be raised if the argument is not an integer. If the rounded value is too large to fit into the result type, an invalid exception is raised, and the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="id1733"></a>

##### Arguments:

The first argument is a floating-point number. The return value is an integer type. Not all types are supported on all targets. The supported types are the same as the `llvm.lrint` intrinsic and the `lrint` libm functions.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1734"></a>

##### Semantics:

This function returns the same values as the libm `lrint` functions would, and handles error conditions in the same way.

The rounding mode is described, not determined, by the rounding mode argument. The actual rounding mode is determined by the runtime floating-point environment. The rounding mode argument is only intended as information to the compiler.

If the runtime floating-point environment is using the default rounding mode then the results will be the same as the `llvm.lrint` intrinsic.

<a id="llvm-experimental-constrained-llrint-intrinsic"></a>

#### ‘`llvm.experimental.constrained.llrint`’ Intrinsic

<a id="id1735"></a>

##### Syntax:

    declare <inttype>
    @llvm.experimental.constrained.llrint(<fptype> <op1>,
                                          metadata <rounding mode>,
                                          metadata <exception behavior>)

<a id="id1736"></a>

##### Overview:

The ‘`llvm.experimental.constrained.llrint`’ intrinsic returns the first argument rounded to the nearest integer. An inexact floating-point exception will be raised if the argument is not an integer. If the rounded value is too large to fit into the result type, an invalid exception is raised, and the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="id1737"></a>

##### Arguments:

The first argument is a floating-point number. The return value is an integer type. Not all types are supported on all targets. The supported types are the same as the `llvm.llrint` intrinsic and the `llrint` libm functions.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1738"></a>

##### Semantics:

This function returns the same values as the libm `llrint` functions would, and handles error conditions in the same way.

The rounding mode is described, not determined, by the rounding mode argument. The actual rounding mode is determined by the runtime floating-point environment. The rounding mode argument is only intended as information to the compiler.

If the runtime floating-point environment is using the default rounding mode then the results will be the same as the `llvm.llrint` intrinsic.

<a id="llvm-experimental-constrained-nearbyint-intrinsic"></a>

#### ‘`llvm.experimental.constrained.nearbyint`’ Intrinsic

<a id="id1739"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.nearbyint(<type> <op1>,
                                             metadata <rounding mode>,
                                             metadata <exception behavior>)

<a id="id1740"></a>

##### Overview:

The ‘`llvm.experimental.constrained.nearbyint`’ intrinsic returns the first argument rounded to the nearest integer. It will not raise an inexact floating-point exception if the argument is not an integer.

<a id="id1741"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second and third arguments specify the rounding mode and exception behavior as described above.

<a id="id1742"></a>

##### Semantics:

This function returns the same values as the libm `nearbyint` functions would, and handles error conditions in the same way. The rounding mode is described, not determined, by the rounding mode argument. The actual rounding mode is determined by the runtime floating-point environment. The rounding mode argument is only intended as information to the compiler.

<a id="llvm-experimental-constrained-maxnum-intrinsic"></a>

#### ‘`llvm.experimental.constrained.maxnum`’ Intrinsic

<a id="id1743"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.maxnum(<type> <op1>, <type> <op2>
                                          metadata <exception behavior>)

<a id="id1744"></a>

##### Overview:

The ‘`llvm.experimental.constrained.maxnum`’ intrinsic returns the maximum of the two arguments.

<a id="id1745"></a>

##### Arguments:

The first two arguments and the return value are floating-point numbers of the same type.

The third argument specifies the exception behavior as described above.

<a id="id1746"></a>

##### Semantics:

This function follows the IEEE 754-2008 semantics for maxNum.

<a id="llvm-experimental-constrained-minnum-intrinsic"></a>

#### ‘`llvm.experimental.constrained.minnum`’ Intrinsic

<a id="id1747"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.minnum(<type> <op1>, <type> <op2>
                                          metadata <exception behavior>)

<a id="id1748"></a>

##### Overview:

The ‘`llvm.experimental.constrained.minnum`’ intrinsic returns the minimum of the two arguments.

<a id="id1749"></a>

##### Arguments:

The first two arguments and the return value are floating-point numbers of the same type.

The third argument specifies the exception behavior as described above.

<a id="id1750"></a>

##### Semantics:

This function follows the IEEE 754-2008 semantics for minNum.

<a id="llvm-experimental-constrained-maximum-intrinsic"></a>

#### ‘`llvm.experimental.constrained.maximum`’ Intrinsic

<a id="id1751"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.maximum(<type> <op1>, <type> <op2>
                                           metadata <exception behavior>)

<a id="id1752"></a>

##### Overview:

The ‘`llvm.experimental.constrained.maximum`’ intrinsic returns the maximum of the two arguments, propagating NaNs and treating -0.0 as less than +0.0.

<a id="id1753"></a>

##### Arguments:

The first two arguments and the return value are floating-point numbers of the same type.

The third argument specifies the exception behavior as described above.

<a id="id1754"></a>

##### Semantics:

This function follows semantics specified in the draft of IEEE 754-2019.

<a id="llvm-experimental-constrained-minimum-intrinsic"></a>

#### ‘`llvm.experimental.constrained.minimum`’ Intrinsic

<a id="id1755"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.minimum(<type> <op1>, <type> <op2>
                                           metadata <exception behavior>)

<a id="id1756"></a>

##### Overview:

The ‘`llvm.experimental.constrained.minimum`’ intrinsic returns the minimum of the two arguments, propagating NaNs and treating -0.0 as less than +0.0.

<a id="id1757"></a>

##### Arguments:

The first two arguments and the return value are floating-point numbers of the same type.

The third argument specifies the exception behavior as described above.

<a id="id1758"></a>

##### Semantics:

This function follows semantics specified in the draft of IEEE 754-2019.

<a id="llvm-experimental-constrained-ceil-intrinsic"></a>

#### ‘`llvm.experimental.constrained.ceil`’ Intrinsic

<a id="id1759"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.ceil(<type> <op1>,
                                        metadata <exception behavior>)

<a id="id1760"></a>

##### Overview:

The ‘`llvm.experimental.constrained.ceil`’ intrinsic returns the ceiling of the first argument.

<a id="id1761"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second argument specifies the exception behavior as described above.

<a id="id1762"></a>

##### Semantics:

This function returns the same values as the libm `ceil` functions would and handles error conditions in the same way.

<a id="llvm-experimental-constrained-floor-intrinsic"></a>

#### ‘`llvm.experimental.constrained.floor`’ Intrinsic

<a id="id1763"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.floor(<type> <op1>,
                                         metadata <exception behavior>)

<a id="id1764"></a>

##### Overview:

The ‘`llvm.experimental.constrained.floor`’ intrinsic returns the floor of the first argument.

<a id="id1765"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second argument specifies the exception behavior as described above.

<a id="id1766"></a>

##### Semantics:

This function returns the same values as the libm `floor` functions would and handles error conditions in the same way.

<a id="llvm-experimental-constrained-round-intrinsic"></a>

#### ‘`llvm.experimental.constrained.round`’ Intrinsic

<a id="id1767"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.round(<type> <op1>,
                                         metadata <exception behavior>)

<a id="id1768"></a>

##### Overview:

The ‘`llvm.experimental.constrained.round`’ intrinsic returns the first argument rounded to the nearest integer.

<a id="id1769"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second argument specifies the exception behavior as described above.

<a id="id1770"></a>

##### Semantics:

This function returns the same values as the libm `round` functions would and handles error conditions in the same way.

<a id="llvm-experimental-constrained-roundeven-intrinsic"></a>

#### ‘`llvm.experimental.constrained.roundeven`’ Intrinsic

<a id="id1771"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.roundeven(<type> <op1>,
                                             metadata <exception behavior>)

<a id="id1772"></a>

##### Overview:

The ‘`llvm.experimental.constrained.roundeven`’ intrinsic returns the first argument rounded to the nearest integer in floating-point format, rounding halfway cases to even (that is, to the nearest value that is an even integer), regardless of the current rounding direction.

<a id="id1773"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second argument specifies the exception behavior as described above.

<a id="id1774"></a>

##### Semantics:

This function implements IEEE 754 operation `roundToIntegralTiesToEven`. It also behaves in the same way as C standard function `roundeven` and can signal the invalid operation exception for a SNAN argument.

<a id="llvm-experimental-constrained-lround-intrinsic"></a>

#### ‘`llvm.experimental.constrained.lround`’ Intrinsic

<a id="id1775"></a>

##### Syntax:

    declare <inttype>
    @llvm.experimental.constrained.lround(<fptype> <op1>,
                                          metadata <exception behavior>)

<a id="id1776"></a>

##### Overview:

The ‘`llvm.experimental.constrained.lround`’ intrinsic returns the first argument rounded to the nearest integer with ties away from zero. It will raise an inexact floating-point exception if the argument is not an integer. If the rounded value is too large to fit into the result type, an invalid exception is raised, and the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="id1777"></a>

##### Arguments:

The first argument is a floating-point number. The return value is an integer type. Not all types are supported on all targets. The supported types are the same as the `llvm.lround` intrinsic and the `lround` libm functions.

The second argument specifies the exception behavior as described above.

<a id="id1778"></a>

##### Semantics:

This function returns the same values as the libm `lround` functions would and handles error conditions in the same way.

<a id="llvm-experimental-constrained-llround-intrinsic"></a>

#### ‘`llvm.experimental.constrained.llround`’ Intrinsic

<a id="id1779"></a>

##### Syntax:

    declare <inttype>
    @llvm.experimental.constrained.llround(<fptype> <op1>,
                                           metadata <exception behavior>)

<a id="id1780"></a>

##### Overview:

The ‘`llvm.experimental.constrained.llround`’ intrinsic returns the first argument rounded to the nearest integer with ties away from zero. It will raise an inexact floating-point exception if the argument is not an integer. If the rounded value is too large to fit into the result type, an invalid exception is raised, and the return value is a non-deterministic value (equivalent to `freeze poison`).

<a id="id1781"></a>

##### Arguments:

The first argument is a floating-point number. The return value is an integer type. Not all types are supported on all targets. The supported types are the same as the `llvm.llround` intrinsic and the `llround` libm functions.

The second argument specifies the exception behavior as described above.

<a id="id1782"></a>

##### Semantics:

This function returns the same values as the libm `llround` functions would and handles error conditions in the same way.

<a id="llvm-experimental-constrained-trunc-intrinsic"></a>

#### ‘`llvm.experimental.constrained.trunc`’ Intrinsic

<a id="id1783"></a>

##### Syntax:

    declare <type>
    @llvm.experimental.constrained.trunc(<type> <op1>,
                                         metadata <exception behavior>)

<a id="id1784"></a>

##### Overview:

The ‘`llvm.experimental.constrained.trunc`’ intrinsic returns the first argument rounded to the nearest integer not larger in magnitude than the argument.

<a id="id1785"></a>

##### Arguments:

The first argument and the return value are floating-point numbers of the same type.

The second argument specifies the exception behavior as described above.

<a id="id1786"></a>

##### Semantics:

This function returns the same values as the libm `trunc` functions would and handles error conditions in the same way.

<a id="llvm-experimental-noalias-scope-decl-intrinsic"></a>

<a id="int-experimental-noalias-scope-decl"></a>

#### ‘`llvm.experimental.noalias.scope.decl`’ Intrinsic

<a id="id1787"></a>

##### Syntax:

    declare void @llvm.experimental.noalias.scope.decl(metadata !id.scope.list)

<a id="id1788"></a>

##### Overview:

The `llvm.experimental.noalias.scope.decl` intrinsic identifies where a noalias scope is declared. When the intrinsic is duplicated, a decision must also be made about the scope: depending on the reason of the duplication, the scope might need to be duplicated as well.

<a id="id1789"></a>

##### Arguments:

The `!id.scope.list` argument is metadata that is a list of `noalias` metadata references. The format is identical to that required for `noalias` metadata. This list must have exactly one element.

<a id="id1790"></a>

##### Semantics:

The `llvm.experimental.noalias.scope.decl` intrinsic identifies where a noalias scope is declared. When the intrinsic is duplicated, a decision must also be made about the scope: depending on the reason of the duplication, the scope might need to be duplicated as well.

For example, when the intrinsic is used inside a loop body, and that loop is unrolled, the associated noalias scope must also be duplicated. Otherwise, the noalias property it signifies would spill across loop iterations, whereas it was only valid within a single iteration.

    ; This example shows two possible positions for noalias.decl and how they impact the semantics:
    ; If it is outside the loop (Version 1), then %a and %b are noalias across *all* iterations.
    ; If it is inside the loop (Version 2), then %a and %b are noalias only within *one* iteration.
    declare void @decl_in_loop(ptr %a.base, ptr %b.base) {
    entry:
      ; call void @llvm.experimental.noalias.scope.decl(metadata !2) ; Version 1: noalias decl outside loop
      br label %loop

    loop:
      %a = phi ptr [ %a.base, %entry ], [ %a.inc, %loop ]
      %b = phi ptr [ %b.base, %entry ], [ %b.inc, %loop ]
      ; call void @llvm.experimental.noalias.scope.decl(metadata !2) ; Version 2: noalias decl inside loop
      %val = load i8, ptr %a, !alias.scope !2
      store i8 %val, ptr %b, !noalias !2
      %a.inc = getelementptr inbounds i8, ptr %a, i64 1
      %b.inc = getelementptr inbounds i8, ptr %b, i64 1
      %cond = call i1 @cond()
      br i1 %cond, label %loop, label %exit

    exit:
      ret void
    }

    !0 = !{!0} ; domain
    !1 = !{!1, !0} ; scope
    !2 = !{!1} ; scope list

Multiple calls to `@llvm.experimental.noalias.scope.decl` for the same scope are possible, but one should never dominate another. Violations are pointed out by the verifier as they indicate a problem in either a transformation pass or the input.

<a id="floating-point-environment-manipulation-intrinsics"></a>

### Floating Point Environment Manipulation intrinsics

These functions read or write floating point environment, such as rounding mode or state of floating point exceptions. Altering the floating point environment requires special care. See [Floating Point Environment](high-level-structure.md#floatenv).

<a id="llvm-get-rounding-intrinsic"></a>

<a id="int-get-rounding"></a>

#### ‘`llvm.get.rounding`’ Intrinsic

<a id="id1791"></a>

##### Syntax:

    declare i32 @llvm.get.rounding()

<a id="id1792"></a>

##### Overview:

The ‘`llvm.get.rounding`’ intrinsic reads the current rounding mode.

<a id="id1793"></a>

##### Semantics:

The ‘`llvm.get.rounding`’ intrinsic returns the current rounding mode. Encoding of the returned values is same as the result of `FLT_ROUNDS`, specified by C standard:

    0  - toward zero
    1  - to nearest, ties to even
    2  - toward positive infinity
    3  - toward negative infinity
    4  - to nearest, ties away from zero

Other values may be used to represent additional rounding modes, supported by a target. These values are target-specific.

<a id="llvm-set-rounding-intrinsic"></a>

<a id="int-set-rounding"></a>

#### ‘`llvm.set.rounding`’ Intrinsic

<a id="id1794"></a>

##### Syntax:

    declare void @llvm.set.rounding(i32 <val>)

<a id="id1795"></a>

##### Overview:

The ‘`llvm.set.rounding`’ intrinsic sets current rounding mode.

<a id="id1796"></a>

##### Arguments:

The argument is the required rounding mode. Encoding of rounding mode is the same as used by ‘`llvm.get.rounding`’.

<a id="id1797"></a>

##### Semantics:

The ‘`llvm.set.rounding`’ intrinsic sets the current rounding mode. It is similar to C library function ‘fesetround’, however this intrinsic does not return any value and uses platform-independent representation of IEEE rounding modes.

<a id="llvm-get-fpenv-intrinsic"></a>

<a id="int-get-fpenv"></a>

#### ‘`llvm.get.fpenv`’ Intrinsic

<a id="id1798"></a>

##### Syntax:

    declare <integer_type> @llvm.get.fpenv()

<a id="id1799"></a>

##### Overview:

The ‘`llvm.get.fpenv`’ intrinsic returns bits of the current floating-point environment. The return value type is platform-specific.

<a id="id1800"></a>

##### Semantics:

The ‘`llvm.get.fpenv`’ intrinsic reads the current floating-point environment and returns it as an integer value.

<a id="llvm-set-fpenv-intrinsic"></a>

<a id="int-set-fpenv"></a>

#### ‘`llvm.set.fpenv`’ Intrinsic

<a id="id1801"></a>

##### Syntax:

    declare void @llvm.set.fpenv(<integer_type> <val>)

<a id="id1802"></a>

##### Overview:

The ‘`llvm.set.fpenv`’ intrinsic sets the current floating-point environment.

<a id="id1803"></a>

##### Arguments:

The argument is an integer representing the new floating-point environment. The integer type is platform-specific.

<a id="id1804"></a>

##### Semantics:

The ‘`llvm.set.fpenv`’ intrinsic sets the current floating-point environment to the state specified by the argument. The state may be previously obtained by a call to ‘`llvm.get.fpenv`’ or synthesized in a platform-dependent way.

<a id="llvm-reset-fpenv-intrinsic"></a>

#### ‘`llvm.reset.fpenv`’ Intrinsic

<a id="id1805"></a>

##### Syntax:

    declare void @llvm.reset.fpenv()

<a id="id1806"></a>

##### Overview:

The ‘`llvm.reset.fpenv`’ intrinsic sets the default floating-point environment.

<a id="id1807"></a>

##### Semantics:

The ‘`llvm.reset.fpenv`’ intrinsic sets the current floating-point environment to default state. It is similar to the call ‘fesetenv(FE_DFL_ENV)’, except it does not return any value.

<a id="llvm-get-fpmode-intrinsic"></a>

<a id="int-get-fpmode"></a>

#### ‘`llvm.get.fpmode`’ Intrinsic

<a id="id1808"></a>

##### Syntax:

The ‘`llvm.get.fpmode`’ intrinsic returns bits of the current floating-point control modes. The return value type is platform-specific.

    declare <integer_type> @llvm.get.fpmode()

<a id="id1809"></a>

##### Overview:

The ‘`llvm.get.fpmode`’ intrinsic reads the current dynamic floating-point control modes and returns it as an integer value.

<a id="id1810"></a>

##### Arguments:

None.

<a id="id1811"></a>

##### Semantics:

The ‘`llvm.get.fpmode`’ intrinsic reads the current dynamic floating-point control modes, such as rounding direction, precision, treatment of denormals and so on. It is similar to the C library function ‘fegetmode’, however this function does not store the set of control modes into memory but returns it as an integer value. Interpretation of the bits in this value is target-dependent.

<a id="llvm-set-fpmode-intrinsic"></a>

#### ‘`llvm.set.fpmode`’ Intrinsic

<a id="id1812"></a>

##### Syntax:

The ‘`llvm.set.fpmode`’ intrinsic sets the current floating-point control modes.

    declare void @llvm.set.fpmode(<integer_type> <val>)

<a id="id1813"></a>

##### Overview:

The ‘`llvm.set.fpmode`’ intrinsic sets the current dynamic floating-point control modes.

<a id="id1814"></a>

##### Arguments:

The argument is a set of floating-point control modes, represented as an integer value in a target-dependent way.

<a id="id1815"></a>

##### Semantics:

The ‘`llvm.set.fpmode`’ intrinsic sets the current dynamic floating-point control modes to the state specified by the argument, which must be obtained by a call to ‘`llvm.get.fpmode`’ or constructed in a target-specific way. It is similar to the C library function ‘fesetmode’, however this function does not read the set of control modes from memory but gets it as integer value.

<a id="llvm-reset-fpmode-intrinsic"></a>

#### ‘`llvm.reset.fpmode`’ Intrinsic

<a id="id1816"></a>

##### Syntax:

    declare void @llvm.reset.fpmode()

<a id="id1817"></a>

##### Overview:

The ‘`llvm.reset.fpmode`’ intrinsic sets the default dynamic floating-point control modes.

<a id="id1818"></a>

##### Arguments:

None.

<a id="id1819"></a>

##### Semantics:

The ‘`llvm.reset.fpmode`’ intrinsic sets the current dynamic floating-point environment to default state. It is similar to the C library function call ‘fesetmode(FE_DFL_MODE)’, however this function does not return any value.

<a id="floating-point-test-intrinsics"></a>

### Floating-Point Test Intrinsics

These functions get properties of floating-point values.

<a id="llvm-is-fpclass-intrinsic"></a>

<a id="llvm-is-fpclass"></a>

#### ‘`llvm.is.fpclass`’ Intrinsic

<a id="id1820"></a>

##### Syntax:

    declare i1 @llvm.is.fpclass(<fptype> <op>, i32 <test>)
    declare <N x i1> @llvm.is.fpclass(<vector-fptype> <op>, i32 <test>)

<a id="id1821"></a>

##### Overview:

The ‘`llvm.is.fpclass`’ intrinsic returns a boolean value or vector of boolean values depending on whether the first argument satisfies the test specified by the second argument.

If the first argument is a floating-point scalar, then the result type is a boolean ([i1](type-system.md#t-integer)).

If the first argument is a floating-point vector, then the result type is a vector of boolean with the same number of elements as the first argument.

<a id="id1822"></a>

##### Arguments:

The first argument to the ‘`llvm.is.fpclass`’ intrinsic must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values.

The second argument specifies, which tests to perform. It must be a compile-time integer constant, each bit in which specifies floating-point class:

| Bit \# | floating-point class |
|--------|----------------------|
| 0      | Signaling NaN        |
| 1      | Quiet NaN            |
| 2      | Negative infinity    |
| 3      | Negative normal      |
| 4      | Negative subnormal   |
| 5      | Negative zero        |
| 6      | Positive zero        |
| 7      | Positive subnormal   |
| 8      | Positive normal      |
| 9      | Positive infinity    |

<a id="id1823"></a>

##### Semantics:

The function checks if `op` belongs to any of the floating-point classes specified by `test`. If `op` is a vector, then the check is made element by element. Each check yields an [i1](type-system.md#t-integer) result, which is `true`, if the element value satisfies the specified test. The argument `test` is a bit mask where each bit specifies floating-point class to test. For example, the value 0x108 makes test for normal value, - bits 3 and 8 in it are set, which means that the function returns `true` if `op` is a positive or negative normal value. The function never raises floating-point exceptions. The function does not canonicalize its input value and does not depend on the floating-point environment. If the floating-point environment has a zeroing treatment of subnormal input values (such as indicated by the [denormal_fpenv](high-level-structure.md#denormal-fpenv) attribute), a subnormal value will be observed (will not be implicitly treated as zero).
