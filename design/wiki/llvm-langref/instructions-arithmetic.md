[Wiki](../index.md) › [LLVM LangRef](index.md)

# Unary, binary, bitwise and byte operations

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="unary-operations"></a>

<a id="unaryops"></a>

### Unary Operations

Unary operators require a single operand, execute an operation on it, and produce a single value. The operand might represent multiple data, as is the case with the [vector](type-system.md#t-vector) data type. The result value has the same type as its operand.

<a id="fneg-instruction"></a>

<a id="i-fneg"></a>

#### ‘`fneg`’ Instruction

<a id="id84"></a>

##### Syntax:

    <result> = fneg [fast-math flags]* <ty> <op1>   ; yields ty:result

<a id="id85"></a>

##### Overview:

The ‘`fneg`’ instruction returns the negation of its operand.

<a id="id86"></a>

##### Arguments:

The argument to the ‘`fneg`’ instruction must be a [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values.

<a id="id87"></a>

##### Semantics:

The value produced is a copy of the operand with its sign bit flipped. The value is otherwise completely identical; in particular, if the input is a NaN, then the quiet/signaling bit and payload are perfectly preserved.

This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations:

<a id="id88"></a>

##### Example:

    <result> = fneg float %val          ; yields float:result = -%var

<a id="binary-operations"></a>

<a id="binaryops"></a>

### Binary Operations

Binary operators are used to do most of the computation in a program. They require two operands of the same type, execute an operation on them, and produce a single value. The operands might represent multiple data, as is the case with the [vector](type-system.md#t-vector) data type. The result value has the same type as its operands.

There are several different binary operators:

<a id="add-instruction"></a>

<a id="i-add"></a>

#### ‘`add`’ Instruction

<a id="id89"></a>

##### Syntax:

    <result> = add <ty> <op1>, <op2>          ; yields ty:result
    <result> = add nuw <ty> <op1>, <op2>      ; yields ty:result
    <result> = add nsw <ty> <op1>, <op2>      ; yields ty:result
    <result> = add nuw nsw <ty> <op1>, <op2>  ; yields ty:result

<a id="id90"></a>

##### Overview:

The ‘`add`’ instruction returns the sum of its two operands.

<a id="id91"></a>

##### Arguments:

The two arguments to the ‘`add`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id92"></a>

##### Semantics:

The value produced is the integer sum of the two operands.

If the sum has unsigned overflow, the result returned is the mathematical result modulo 2<sup>n</sup>, where n is the bit width of the result.

Because LLVM integers use a two’s complement representation, this instruction is appropriate for both signed and unsigned integers.

`nuw` and `nsw` stand for “No Unsigned Wrap” and “No Signed Wrap”, respectively. If the `nuw` and/or `nsw` keywords are present, the result value of the `add` is a [poison value](constants.md#poisonvalues) if unsigned and/or signed overflow, respectively, occurs.

<a id="id93"></a>

##### Example:

    <result> = add i32 4, %var          ; yields i32:result = 4 + %var

<a id="fadd-instruction"></a>

<a id="i-fadd"></a>

#### ‘`fadd`’ Instruction

<a id="id94"></a>

##### Syntax:

    <result> = fadd [fast-math flags]* <ty> <op1>, <op2>   ; yields ty:result

<a id="id95"></a>

##### Overview:

The ‘`fadd`’ instruction returns the sum of its two operands.

<a id="id96"></a>

##### Arguments:

The two arguments to the ‘`fadd`’ instruction must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

<a id="id97"></a>

##### Semantics:

The value produced is the floating-point sum of the two operands. This instruction is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv). This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations:

<a id="id98"></a>

##### Example:

    <result> = fadd float 4.0, %var          ; yields float:result = 4.0 + %var

<a id="sub-instruction"></a>

<a id="i-sub"></a>

#### ‘`sub`’ Instruction

<a id="id99"></a>

##### Syntax:

    <result> = sub <ty> <op1>, <op2>          ; yields ty:result
    <result> = sub nuw <ty> <op1>, <op2>      ; yields ty:result
    <result> = sub nsw <ty> <op1>, <op2>      ; yields ty:result
    <result> = sub nuw nsw <ty> <op1>, <op2>  ; yields ty:result

<a id="id100"></a>

##### Overview:

The ‘`sub`’ instruction returns the difference of its two operands.

Note that the ‘`sub`’ instruction is used to represent the ‘`neg`’ instruction present in most other intermediate representations.

<a id="id101"></a>

##### Arguments:

The two arguments to the ‘`sub`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id102"></a>

##### Semantics:

The value produced is the integer difference of the two operands.

If the difference has unsigned overflow, the result returned is the mathematical result modulo 2<sup>n</sup>, where n is the bit width of the result.

Because LLVM integers use a two’s complement representation, this instruction is appropriate for both signed and unsigned integers.

`nuw` and `nsw` stand for “No Unsigned Wrap” and “No Signed Wrap”, respectively. If the `nuw` and/or `nsw` keywords are present, the result value of the `sub` is a [poison value](constants.md#poisonvalues) if unsigned and/or signed overflow, respectively, occurs.

<a id="id103"></a>

##### Example:

    <result> = sub i32 4, %var          ; yields i32:result = 4 - %var
    <result> = sub i32 0, %val          ; yields i32:result = -%var

<a id="fsub-instruction"></a>

<a id="i-fsub"></a>

#### ‘`fsub`’ Instruction

<a id="id104"></a>

##### Syntax:

    <result> = fsub [fast-math flags]* <ty> <op1>, <op2>   ; yields ty:result

<a id="id105"></a>

##### Overview:

The ‘`fsub`’ instruction returns the difference of its two operands.

<a id="id106"></a>

##### Arguments:

The two arguments to the ‘`fsub`’ instruction must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

<a id="id107"></a>

##### Semantics:

The value produced is the floating-point difference of the two operands. This instruction is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv). This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations:

<a id="id108"></a>

##### Example:

    <result> = fsub float 4.0, %var           ; yields float:result = 4.0 - %var
    <result> = fsub float -0.0, %val          ; yields float:result = -%var

<a id="mul-instruction"></a>

<a id="i-mul"></a>

#### ‘`mul`’ Instruction

<a id="id109"></a>

##### Syntax:

    <result> = mul <ty> <op1>, <op2>          ; yields ty:result
    <result> = mul nuw <ty> <op1>, <op2>      ; yields ty:result
    <result> = mul nsw <ty> <op1>, <op2>      ; yields ty:result
    <result> = mul nuw nsw <ty> <op1>, <op2>  ; yields ty:result

<a id="id110"></a>

##### Overview:

The ‘`mul`’ instruction returns the product of its two operands.

<a id="id111"></a>

##### Arguments:

The two arguments to the ‘`mul`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id112"></a>

##### Semantics:

The value produced is the integer product of the two operands.

If the result of the multiplication has unsigned overflow, the result returned is the mathematical result modulo 2<sup>n</sup>, where n is the bit width of the result.

Because LLVM integers use a two’s complement representation, and the result is the same width as the operands, this instruction returns the correct result for both signed and unsigned integers. If a full product (e.g., `i32` \* `i32` -\> `i64`) is needed, the operands should be sign-extended or zero-extended as appropriate to the width of the full product.

`nuw` and `nsw` stand for “No Unsigned Wrap” and “No Signed Wrap”, respectively. If the `nuw` and/or `nsw` keywords are present, the result value of the `mul` is a [poison value](constants.md#poisonvalues) if unsigned and/or signed overflow, respectively, occurs.

<a id="id113"></a>

##### Example:

    <result> = mul i32 4, %var          ; yields i32:result = 4 * %var

<a id="fmul-instruction"></a>

<a id="i-fmul"></a>

#### ‘`fmul`’ Instruction

<a id="id114"></a>

##### Syntax:

    <result> = fmul [fast-math flags]* <ty> <op1>, <op2>   ; yields ty:result

<a id="id115"></a>

##### Overview:

The ‘`fmul`’ instruction returns the product of its two operands.

<a id="id116"></a>

##### Arguments:

The two arguments to the ‘`fmul`’ instruction must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

<a id="id117"></a>

##### Semantics:

The value produced is the floating-point product of the two operands. This instruction is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv). This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations:

<a id="id118"></a>

##### Example:

    <result> = fmul float 4.0, %var          ; yields float:result = 4.0 * %var

<a id="udiv-instruction"></a>

<a id="i-udiv"></a>

#### ‘`udiv`’ Instruction

<a id="id119"></a>

##### Syntax:

    <result> = udiv <ty> <op1>, <op2>         ; yields ty:result
    <result> = udiv exact <ty> <op1>, <op2>   ; yields ty:result

<a id="id120"></a>

##### Overview:

The ‘`udiv`’ instruction returns the quotient of its two operands.

<a id="id121"></a>

##### Arguments:

The two arguments to the ‘`udiv`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id122"></a>

##### Semantics:

The value produced is the unsigned integer quotient of the two operands.

Note that unsigned integer division and signed integer division are distinct operations; for signed integer division, use ‘`sdiv`’.

Division by zero is undefined behavior. For vectors, if any element of the divisor is zero, the operation has undefined behavior.

If the `exact` keyword is present, the result value of the `udiv` is a [poison value](constants.md#poisonvalues) if %op1 is not a multiple of %op2 (as such, “((a udiv exact b) mul b) == a”).

<a id="id123"></a>

##### Example:

    <result> = udiv i32 4, %var          ; yields i32:result = 4 / %var

<a id="sdiv-instruction"></a>

<a id="i-sdiv"></a>

#### ‘`sdiv`’ Instruction

<a id="id124"></a>

##### Syntax:

    <result> = sdiv <ty> <op1>, <op2>         ; yields ty:result
    <result> = sdiv exact <ty> <op1>, <op2>   ; yields ty:result

<a id="id125"></a>

##### Overview:

The ‘`sdiv`’ instruction returns the quotient of its two operands.

<a id="id126"></a>

##### Arguments:

The two arguments to the ‘`sdiv`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id127"></a>

##### Semantics:

The value produced is the signed integer quotient of the two operands rounded towards zero.

Note that signed integer division and unsigned integer division are distinct operations; for unsigned integer division, use ‘`udiv`’.

Division by zero is undefined behavior. For vectors, if any element of the divisor is zero, the operation has undefined behavior. Overflow also leads to undefined behavior; this is a rare case, but can occur, for example, by doing a 32-bit division of -2147483648 by -1.

If the `exact` keyword is present, the result value of the `sdiv` is a [poison value](constants.md#poisonvalues) if the result would be rounded.

<a id="id128"></a>

##### Example:

    <result> = sdiv i32 4, %var          ; yields i32:result = 4 / %var

<a id="fdiv-instruction"></a>

<a id="i-fdiv"></a>

#### ‘`fdiv`’ Instruction

<a id="id129"></a>

##### Syntax:

    <result> = fdiv [fast-math flags]* <ty> <op1>, <op2>   ; yields ty:result

<a id="id130"></a>

##### Overview:

The ‘`fdiv`’ instruction returns the quotient of its two operands.

<a id="id131"></a>

##### Arguments:

The two arguments to the ‘`fdiv`’ instruction must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

<a id="id132"></a>

##### Semantics:

The value produced is the floating-point quotient of the two operands. This instruction is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv). This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations:

<a id="id133"></a>

##### Example:

    <result> = fdiv float 4.0, %var          ; yields float:result = 4.0 / %var

<a id="urem-instruction"></a>

<a id="i-urem"></a>

#### ‘`urem`’ Instruction

<a id="id134"></a>

##### Syntax:

    <result> = urem <ty> <op1>, <op2>   ; yields ty:result

<a id="id135"></a>

##### Overview:

The ‘`urem`’ instruction returns the remainder from the unsigned division of its two arguments.

<a id="id136"></a>

##### Arguments:

The two arguments to the ‘`urem`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id137"></a>

##### Semantics:

This instruction returns the unsigned integer *remainder* of a division. This instruction always performs an unsigned division to get the remainder.

Note that unsigned integer remainder and signed integer remainder are distinct operations; for signed integer remainder, use ‘`srem`’.

Taking the remainder of a division by zero is undefined behavior. For vectors, if any element of the divisor is zero, the operation has undefined behavior.

<a id="id138"></a>

##### Example:

    <result> = urem i32 4, %var          ; yields i32:result = 4 % %var

<a id="srem-instruction"></a>

<a id="i-srem"></a>

#### ‘`srem`’ Instruction

<a id="id139"></a>

##### Syntax:

    <result> = srem <ty> <op1>, <op2>   ; yields ty:result

<a id="id140"></a>

##### Overview:

The ‘`srem`’ instruction returns the remainder from the signed division of its two operands. This instruction can also take [vector](type-system.md#t-vector) versions of the values in which case the elements must be integers.

<a id="id141"></a>

##### Arguments:

The two arguments to the ‘`srem`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id142"></a>

##### Semantics:

This instruction returns the *remainder* of a division (where the result is either zero or has the same sign as the dividend, `op1`), not the *modulo* operator (where the result is either zero or has the same sign as the divisor, `op2`) of a value. For more information about the difference, see [The Math Forum](http://mathforum.org/dr.math/problems/anne.4.28.99.html). For a table of how this is implemented in various languages, please see [Wikipedia: modulo operation](http://en.wikipedia.org/wiki/Modulo_operation).

Note that signed integer remainder and unsigned integer remainder are distinct operations; for unsigned integer remainder, use ‘`urem`’.

Taking the remainder of a division by zero is undefined behavior. For vectors, if any element of the divisor is zero, the operation has undefined behavior. Overflow also leads to undefined behavior; this is a rare case, but can occur, for example, by taking the remainder of a 32-bit division of -2147483648 by -1. (The remainder doesn’t actually overflow, but this rule lets srem be implemented using instructions that return both the result of the division and the remainder.)

<a id="id143"></a>

##### Example:

    <result> = srem i32 4, %var          ; yields i32:result = 4 % %var

<a id="frem-instruction"></a>

<a id="i-frem"></a>

#### ‘`frem`’ Instruction

<a id="id144"></a>

##### Syntax:

    <result> = frem [fast-math flags]* <ty> <op1>, <op2>   ; yields ty:result

<a id="id145"></a>

##### Overview:

The ‘`frem`’ instruction returns the remainder from the division of its two operands.

Note

The instruction is implemented as a call to libm’s ‘`fmod`’ for some targets, and using the instruction may thus require linking libm.

<a id="id146"></a>

##### Arguments:

The two arguments to the ‘`frem`’ instruction must be [floating-point](type-system.md#t-floating) or [vector](type-system.md#t-vector) of floating-point values. Both arguments must have identical types.

<a id="id147"></a>

##### Semantics:

The value produced is the floating-point remainder of the two operands. This is the same output as a libm ‘`fmod`’ function, but without any possibility of setting `errno`. The remainder has the same sign as the dividend. This instruction is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv). This instruction can also take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations:

<a id="id148"></a>

##### Example:

    <result> = frem float 4.0, %var          ; yields float:result = 4.0 % %var

<a id="bitwise-binary-operations"></a>

<a id="bitwiseops"></a>

### Bitwise Binary Operations

Bitwise binary operators are used to do various forms of bit-twiddling in a program. They are generally very efficient instructions and can commonly be strength reduced from other instructions. They require two operands of the same type, execute an operation on them, and produce a single value. The resulting value is the same type as its operands.

<a id="shl-instruction"></a>

<a id="i-shl"></a>

#### ‘`shl`’ Instruction

<a id="id149"></a>

##### Syntax:

    <result> = shl <ty> <op1>, <op2>           ; yields ty:result
    <result> = shl nuw <ty> <op1>, <op2>       ; yields ty:result
    <result> = shl nsw <ty> <op1>, <op2>       ; yields ty:result
    <result> = shl nuw nsw <ty> <op1>, <op2>   ; yields ty:result

<a id="id150"></a>

##### Overview:

The ‘`shl`’ instruction returns the first operand shifted to the left a specified number of bits.

<a id="id151"></a>

##### Arguments:

Both arguments to the ‘`shl`’ instruction must be the same [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer type. ‘`op2`’ is treated as an unsigned value.

<a id="id152"></a>

##### Semantics:

The value produced is `op1` \* 2<sup>op2</sup> mod 2<sup>n</sup>, where `n` is the width of the result. If `op2` is (statically or dynamically) equal to or larger than the number of bits in `op1`, this instruction returns a [poison value](constants.md#poisonvalues). If the arguments are vectors, each vector element of `op1` is shifted by the corresponding shift amount in `op2`.

If the `nuw` keyword is present, then the shift produces a poison value if it shifts out any non-zero bits. If the `nsw` keyword is present, then the shift produces a poison value if it shifts out any bits that disagree with the resultant sign bit.

<a id="id153"></a>

##### Example:

    <result> = shl i32 4, %var   ; yields i32: 4 << %var
    <result> = shl i32 4, 2      ; yields i32: 16
    <result> = shl i32 1, 10     ; yields i32: 1024
    <result> = shl i32 1, 32     ; undefined
    <result> = shl <2 x i32> < i32 1, i32 1>, < i32 1, i32 2>   ; yields: result=<2 x i32> < i32 2, i32 4>

<a id="lshr-instruction"></a>

<a id="i-lshr"></a>

#### ‘`lshr`’ Instruction

<a id="id154"></a>

##### Syntax:

    <result> = lshr <ty> <op1>, <op2>         ; yields ty:result
    <result> = lshr exact <ty> <op1>, <op2>   ; yields ty:result

<a id="id155"></a>

##### Overview:

The ‘`lshr`’ instruction (logical shift right) returns the first operand shifted to the right a specified number of bits with zero fill.

<a id="id156"></a>

##### Arguments:

Both arguments to the ‘`lshr`’ instruction must be the same [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer type. ‘`op2`’ is treated as an unsigned value.

<a id="id157"></a>

##### Semantics:

This instruction always performs a logical shift right operation. The most significant bits of the result will be filled with zero bits after the shift. If `op2` is (statically or dynamically) equal to or larger than the number of bits in `op1`, this instruction returns a [poison value](constants.md#poisonvalues). If the arguments are vectors, each vector element of `op1` is shifted by the corresponding shift amount in `op2`.

If the `exact` keyword is present, the result value of the `lshr` is a poison value if any of the bits shifted out are non-zero.

<a id="id158"></a>

##### Example:

    <result> = lshr i32 4, 1   ; yields i32:result = 2
    <result> = lshr i32 4, 2   ; yields i32:result = 1
    <result> = lshr i8  4, 3   ; yields i8:result = 0
    <result> = lshr i8 -2, 1   ; yields i8:result = 0x7F
    <result> = lshr i32 1, 32  ; undefined
    <result> = lshr <2 x i32> < i32 -2, i32 4>, < i32 1, i32 2>   ; yields: result=<2 x i32> < i32 0x7FFFFFFF, i32 1>

<a id="ashr-instruction"></a>

<a id="i-ashr"></a>

#### ‘`ashr`’ Instruction

<a id="id159"></a>

##### Syntax:

    <result> = ashr <ty> <op1>, <op2>         ; yields ty:result
    <result> = ashr exact <ty> <op1>, <op2>   ; yields ty:result

<a id="id160"></a>

##### Overview:

The ‘`ashr`’ instruction (arithmetic shift right) returns the first operand shifted to the right a specified number of bits with sign extension.

<a id="id161"></a>

##### Arguments:

Both arguments to the ‘`ashr`’ instruction must be the same [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer type. ‘`op2`’ is treated as an unsigned value.

<a id="id162"></a>

##### Semantics:

This instruction always performs an arithmetic shift right operation, The most significant bits of the result will be filled with the sign bit of `op1`. If `op2` is (statically or dynamically) equal to or larger than the number of bits in `op1`, this instruction returns a [poison value](constants.md#poisonvalues). If the arguments are vectors, each vector element of `op1` is shifted by the corresponding shift amount in `op2`.

If the `exact` keyword is present, the result value of the `ashr` is a poison value if any of the bits shifted out are non-zero.

<a id="id163"></a>

##### Example:

    <result> = ashr i32 4, 1   ; yields i32:result = 2
    <result> = ashr i32 4, 2   ; yields i32:result = 1
    <result> = ashr i8  4, 3   ; yields i8:result = 0
    <result> = ashr i8 -2, 1   ; yields i8:result = -1
    <result> = ashr i32 1, 32  ; undefined
    <result> = ashr <2 x i32> < i32 -2, i32 4>, < i32 1, i32 3>   ; yields: result=<2 x i32> < i32 -1, i32 0>

<a id="and-instruction"></a>

<a id="i-and"></a>

#### ‘`and`’ Instruction

<a id="id164"></a>

##### Syntax:

    <result> = and <ty> <op1>, <op2>   ; yields ty:result

<a id="id165"></a>

##### Overview:

The ‘`and`’ instruction returns the bitwise logical and of its two operands.

<a id="id166"></a>

##### Arguments:

The two arguments to the ‘`and`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id167"></a>

##### Semantics:

The truth table used for the ‘`and`’ instruction is:

| In0 | In1 | Out |
|-----|-----|-----|
| 0   | 0   | 0   |
| 0   | 1   | 0   |
| 1   | 0   | 0   |
| 1   | 1   | 1   |

<a id="id168"></a>

##### Example:

    <result> = and i32 4, %var         ; yields i32:result = 4 & %var
    <result> = and i32 15, 40          ; yields i32:result = 8
    <result> = and i32 4, 8            ; yields i32:result = 0

<a id="or-instruction"></a>

<a id="i-or"></a>

#### ‘`or`’ Instruction

<a id="id169"></a>

##### Syntax:

    <result> = or <ty> <op1>, <op2>   ; yields ty:result
    <result> = or disjoint <ty> <op1>, <op2>   ; yields ty:result

<a id="id170"></a>

##### Overview:

The ‘`or`’ instruction returns the bitwise logical inclusive or of its two operands.

<a id="id171"></a>

##### Arguments:

The two arguments to the ‘`or`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id172"></a>

##### Semantics:

The truth table used for the ‘`or`’ instruction is:

| In0 | In1 | Out |
|-----|-----|-----|
| 0   | 0   | 0   |
| 0   | 1   | 1   |
| 1   | 0   | 1   |
| 1   | 1   | 1   |

`disjoint` means that for each bit, that bit is zero in at least one of the inputs. This allows the Or to be treated as an Add since no carry can occur from any bit. If the disjoint keyword is present, the result value of the `or` is a [poison value](constants.md#poisonvalues) if both inputs have a one in the same bit position. For vectors, only the element containing the bit is poison.

<a id="id173"></a>

##### Example:

    <result> = or i32 4, %var         ; yields i32:result = 4 | %var
    <result> = or i32 15, 40          ; yields i32:result = 47
    <result> = or i32 4, 8            ; yields i32:result = 12

<a id="xor-instruction"></a>

<a id="i-xor"></a>

#### ‘`xor`’ Instruction

<a id="id174"></a>

##### Syntax:

    <result> = xor <ty> <op1>, <op2>   ; yields ty:result

<a id="id175"></a>

##### Overview:

The ‘`xor`’ instruction returns the bitwise logical exclusive or of its two operands. The `xor` is used to implement the “one’s complement” operation, which is the “~” operator in C.

<a id="id176"></a>

##### Arguments:

The two arguments to the ‘`xor`’ instruction must be [integer](type-system.md#t-integer) or [vector](type-system.md#t-vector) of integer values. Both arguments must have identical types.

<a id="id177"></a>

##### Semantics:

The truth table used for the ‘`xor`’ instruction is:

| In0 | In1 | Out |
|-----|-----|-----|
| 0   | 0   | 0   |
| 0   | 1   | 1   |
| 1   | 0   | 1   |
| 1   | 1   | 0   |

<a id="id178"></a>

##### Example:

    <result> = xor i32 4, %var         ; yields i32:result = 4 ^ %var
    <result> = xor i32 15, 40          ; yields i32:result = 39
    <result> = xor i32 4, 8            ; yields i32:result = 12
    <result> = xor i32 %V, -1          ; yields i32:result = ~%V
