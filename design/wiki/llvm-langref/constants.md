[Wiki](../index.md) › [LLVM LangRef](index.md)

# Constants and other values

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="constants"></a>

<a id="id5"></a>

## Constants

LLVM has several different basic types of constants. This section describes them all and their syntax.

<a id="simple-constants"></a>

### Simple Constants

**Boolean constants**  
The two strings ‘`true`’ and ‘`false`’ are both valid constants of the `i1` type.

**Integer constants**  
Standard integers (such as ‘4’) are constants of the [integer](type-system.md#t-integer) type. They can be either decimal or hexadecimal. Decimal integers can be prefixed with - to represent negative integers, e.g., ‘`-1234`’. Hexadecimal integers must be prefixed with either u or s to indicate whether they are unsigned or signed respectively. e.g ‘`u0x8000`’ gives 32768, whilst ‘`s0x8000`’ gives -32768.

Note that hexadecimal integers are sign extended from the number of active bits, i.e., the bit width minus the number of leading zeros. So ‘`s0x0001`’ of type ‘`i16`’ will be -1, not 1.

**Byte constants**  
Byte constants are used to initialize global variables of the [byte](type-system.md#t-byte) type. These are strictly equivalent to integer constants: `store b8 42, ptr %p` is equivalent to `store i8 42, ptr %p`.

**Floating-point constants**  
Floating-point constants use standard decimal notation (e.g. 123.421), exponential notation (e.g. 1.23421e+2), standard hexadecimal notation (e.g., 0x1.3effp-43), one of several special values, or a precise bitstring for the underlying value. When converting decimal and hexadecimal literals to the floating-point type, the value is converted using the default rounding mode (round to nearest, half to even). String conversions that underflow to 0 or overflow to infinity are not permitted. Floating-point constants must have a [floating-point](type-system.md#t-floating) type.

**Null pointer constants**  
The identifier ‘`null`’ is recognized as a null pointer constant and must be of [pointer type](type-system.md#t-pointer).

**Token constants**  
The identifier ‘`none`’ is recognized as an empty token constant and must be of [token type](type-system.md#t-token).

Floating-point constants support the following kinds of strings:

| Syntax           | Description                                                                                                                                                                     |
|------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `+4.5e-13`       | Common decimal literal. Signs are optional, as is the exponent portion. The decimal point is required, as is one or more leading digits before the decimal point.               |
| `-0x1.fp13`      | Common hexadecimal literal. Signs are optional. The decimal point is required, as is the exponent portion of the literal (after the `p`).                                       |
| `+inf`, `-inf`   | Positive or negative infinity. The sign is required.                                                                                                                            |
| `+qnan`, `-qnan` | Positive or negative preferred quiet NaN, i.e., the quiet bit is set, and all other payload bits are 0. The sign is required.                                                   |
| `+nan(0x1)`      | qNaN value with a particular payload, specified as hexadecimal (not including the quiet bit as part of the payload). The sign is required.                                      |
| `+snan(0x1)`     | sNaN value with a particular payload, specified as hexadecimal (not including the quiet bit as part of the payload). The sign is required.                                      |
| `f0x3c00`        | Value of the floating-point number if bitcast to an integer. The number must have exactly as many hexadecimal digits as is necessary for the size of the floating-point number. |

There is a legacy syntax for hexadecimal floating-point literals that will be removed in the future. In this format, constants are represented as their underlying integer representation as in the `f0x3c00` syntax, but instead use slightly different prefixes. `float` and `double` use `0x` followed by 16 hexadecimal digits representing the equivalent `double` value bitcast to an integer type. `bfloat` uses `0xR` followed by 4 hexadecimal digits. `half` uses `0xH` followed by 4 hexadecimal digits. `x86_fp80` uses `0xK` followed by 20 hexadecimal digits. `ppc_fp128` uses `0xM` followed by 32 hexadecimal digits. `fp128` uses `0xL` followed by 32 hexadecimal digits. For the last two types only, the bits are not fully written in big-endian order but rather with the low 64 bits written in big-endian then the high 64 bits written in big-endian.

There are no constants of type x86_amx.

<a id="complex-constants"></a>

<a id="complexconstants"></a>

### Complex Constants

Complex constants are a (potentially recursive) combination of simple constants and smaller complex constants.

**Structure constants**  
Structure constants are represented with notation similar to structure type definitions (a comma separated list of elements, surrounded by braces (`{}`)). For example: “`{ i32 4, float 17.0, ptr @G }`”, where “`@G`” is declared as “`@G = external global i32`”. Structure constants must have [structure type](type-system.md#t-struct), and the number and types of elements must match those specified by the type.

**Array constants**  
Array constants are represented with notation similar to array type definitions (a comma separated list of elements, surrounded by square brackets (`[]`)). For example: “`[ i32 42, i32 11, i32 74 ]`”. Array constants must have [array type](type-system.md#t-array), and the number and types of elements must match those specified by the type. As a special case, character array constants may also be represented as a double-quoted string using the `c` prefix. For example: “`c"Hello World\0A\00"`”.

**Vector constants**  
Vector constants are represented with notation similar to vector type definitions (a comma separated list of elements, surrounded by less-than/greater-than’s (`<>`)). For example: “`< i32 42, i32 11, i32 74, i32 100 >`”. Vector constants must have [vector type](type-system.md#t-vector), and the number and types of elements must match those specified by the type.

When creating a vector whose elements have the same constant value, the preferred syntax is `splat (<Ty> Val)`. For example: “`splat (i32 11)`”. These vector constants must have [vector type](type-system.md#t-vector) with an element type that matches the `splat` operand.

**Zero initialization**  
The string ‘`zeroinitializer`’ can be used to zero initialize a value to zero of *any* type, including scalar and [aggregate](type-system.md#t-aggregate) types. This is often used to avoid having to print large zero initializers (e.g., for large arrays) and is always exactly equivalent to using explicit zero initializers.

**Metadata node**  
A metadata node is a constant tuple without types. For example: “`!{!0, !{!2, !0}, !"test"}`”. Metadata can reference constant values, for example: “`!{!0, i32 0, ptr @global, ptr @function, !"str"}`”. Unlike other typed constants that are meant to be interpreted as part of the instruction stream, metadata is a place to attach additional information such as debug info.

<a id="global-variable-and-function-addresses"></a>

### Global Variable and Function Addresses

The addresses of [global variables](high-level-structure.md#globalvars) and [functions](high-level-structure.md#functionstructure) are always implicitly valid (link-time) constants. These constants are explicitly referenced when the [identifier for the global](introduction.md#identifiers) is used and always have [pointer](type-system.md#t-pointer) type. For example, the following is a legal LLVM file:

    @X = global i32 17
    @Y = global i32 42
    @Z = global [2 x ptr] [ ptr @X, ptr @Y ]

<a id="undefined-values"></a>

<a id="undefvalues"></a>

### Undefined Values

The string ‘`undef`’ can be used anywhere a constant is expected, and indicates that the user of the value may receive an unspecified bit-pattern. Undefined values may be of any type (other than ‘`label`’ or ‘`void`’) and be used anywhere a constant is permitted.

Note

A ‘`poison`’ value (described in the next section) should be used instead of ‘`undef`’ whenever possible. Poison values are stronger than undef, and enable more optimizations. Just the existence of ‘`undef`’ blocks certain optimizations (see the examples below).

Undefined values are useful because they indicate to the compiler that the program is well defined no matter what value is used. This gives the compiler more freedom to optimize. Here are some examples of (potentially surprising) transformations that are valid (in pseudo IR):

      %A = add %X, undef
      %B = sub %X, undef
      %C = xor %X, undef
    Safe:
      %A = undef
      %B = undef
      %C = undef

This is safe because all of the output bits are affected by the undef bits. Any output bit can have a zero or one depending on the input bits.

      %A = or %X, undef
      %B = and %X, undef
    Safe:
      %A = -1
      %B = 0
    Safe:
      %A = %X  ;; By choosing undef as 0
      %B = %X  ;; By choosing undef as -1
    Unsafe:
      %A = undef
      %B = undef

These logical operations have bits that are not always affected by the input. For example, if `%X` has a zero bit, then the output of the ‘`and`’ operation will always be a zero for that bit, no matter what the corresponding bit from the ‘`undef`’ is. As such, it is unsafe to optimize or assume that the result of the ‘`and`’ is ‘`undef`’. However, it is safe to assume that all bits of the ‘`undef`’ could be 0, and optimize the ‘`and`’ to 0. Likewise, it is safe to assume that all the bits of the ‘`undef`’ operand to the ‘`or`’ could be set, allowing the ‘`or`’ to be folded to -1.

      %A = select undef, %X, %Y
      %B = select undef, 42, %Y
      %C = select %X, %Y, undef
    Safe:
      %A = %X     (or %Y)
      %B = 42     (or %Y)
      %C = %Y     (if %Y is provably not poison; unsafe otherwise)
    Unsafe:
      %A = undef
      %B = undef
      %C = undef

This set of examples shows that undefined ‘`select`’ conditions can go *either way*, but they have to come from one of the two operands. In the `%A` example, if `%X` and `%Y` were both known to have a clear low bit, then `%A` would have to have a cleared low bit. However, in the `%C` example, the optimizer is allowed to assume that the ‘`undef`’ operand could be the same as `%Y` if `%Y` is provably not ‘`poison`’, allowing the whole ‘`select`’ to be eliminated. This is because ‘`poison`’ is stronger than ‘`undef`’.

      %A = xor undef, undef

      %B = undef
      %C = xor %B, %B

      %D = undef
      %E = icmp slt %D, 4
      %F = icmp sge %D, 4

    Safe:
      %A = undef
      %B = undef
      %C = undef
      %D = undef
      %E = undef
      %F = undef

This example points out that two ‘`undef`’ operands are not necessarily the same. This can be surprising to people (and also matches C semantics) where they assume that “`X^X`” is always zero, even if `X` is undefined. This isn’t true for a number of reasons, but the short answer is that an ‘`undef`’ “variable” can arbitrarily change its value over its “live range”. This is true because the variable doesn’t actually *have a live range*. Instead, the value is logically read from arbitrary registers that happen to be around when needed, so the value is not necessarily consistent over time. In fact, `%A` and `%C` need to have the same semantics or the core LLVM “replace all uses with” concept would not hold.

To ensure all uses of a given register observe the same value (even if ‘`undef`’), the [freeze instruction](instructions-other.md#i-freeze) can be used.

      %A = sdiv undef, %X
      %B = sdiv %X, undef
    Safe:
      %A = 0
    b: unreachable

These examples show the crucial difference between an *undefined value* and *undefined behavior*. An undefined value (like ‘`undef`’) is allowed to have an arbitrary bit-pattern. This means that the `%A` operation can be constant folded to ‘`0`’, because the ‘`undef`’ could be zero, and zero divided by any value is zero. However, in the second example, we can make a more aggressive assumption: because the `undef` is allowed to be an arbitrary value, we are allowed to assume that it could be zero. Since a divide by zero has *undefined behavior*, we are allowed to assume that the operation does not execute at all. This allows us to delete the divide and all code after it. Because the undefined operation “can’t happen”, the optimizer can assume that it occurs in dead code.

    a:  store undef -> %X
    b:  store %X -> undef
    Safe:
    a: <deleted>     (if the stored value in %X is provably not poison)
    b: unreachable

A store *of* an undefined value can be assumed to not have any effect; we can assume that the value is overwritten with bits that happen to match what was already there. This argument is only valid if the stored value is provably not `poison`. However, a store *to* an undefined location could clobber arbitrary memory, therefore, it has undefined behavior.

Branching on an undefined value is undefined behavior. This explains optimizations that depend on branch conditions to construct predicates, such as Correlated Value Propagation and Global Value Numbering. In case of switch instruction, the branch condition should be frozen, otherwise it is undefined behavior.

    Unsafe:
      br undef, BB1, BB2 ; UB

      %X = and i32 undef, 255
      switch %X, label %ret [ .. ] ; UB

      store undef, ptr %ptr
      %X = load ptr %ptr ; %X is undef
      switch i8 %X, label %ret [ .. ] ; UB

    Safe:
      %X = or i8 undef, 255 ; always 255
      switch i8 %X, label %ret [ .. ] ; Well-defined

      %X = freeze i1 undef
      br %X, BB1, BB2 ; Well-defined (non-deterministic jump)

<a id="poison-values"></a>

<a id="poisonvalues"></a>

### Poison Values

A poison value is a result of an erroneous operation. In order to facilitate speculative execution, many instructions do not invoke immediate undefined behavior when provided with illegal operands, and return a poison value instead. The string ‘`poison`’ can be used anywhere a constant is expected, and operations such as [add](instructions-arithmetic.md#i-add) with the `nsw` flag can produce a poison value.

Most instructions return ‘`poison`’ when one of their arguments is ‘`poison`’. A notable exception is the [select instruction](instructions-other.md#i-select). Propagation of poison can be stopped with the [freeze instruction](instructions-other.md#i-freeze).

It is correct to replace a poison value with an [undef value](#undefvalues) or any value of the type.

This means that immediate undefined behavior occurs if a poison value is used as an instruction operand that has any values that trigger undefined behavior. Notably this includes (but is not limited to):

- The pointer operand of a [load](instructions-memory.md#i-load), [store](instructions-memory.md#i-store) or any other pointer dereferencing instruction (independent of address space).

- The divisor operand of a `udiv`, `sdiv`, `urem` or `srem` instruction.

- The condition operand of a [br](instructions-terminators.md#i-br) instruction.

- The callee operand of a [call](instructions-other.md#i-call) or [invoke](instructions-terminators.md#i-invoke) instruction.

- The parameter operand of a [call](instructions-other.md#i-call) or [invoke](instructions-terminators.md#i-invoke) instruction, when the function or invoking call site has a `noundef` attribute in the corresponding position.

- The operand of a [ret](instructions-terminators.md#i-ret) instruction if the function or invoking call site has a `noundef` attribute in the return value position.

Here are some examples:

    entry:
      %poison = sub nuw i32 0, 1           ; Results in a poison value.
      %poison2 = sub i32 poison, 1         ; Also results in a poison value.
      %still_poison = and i32 %poison, 0   ; 0, but also poison.
      %poison_yet_again = getelementptr i32, ptr @h, i32 %still_poison
      store i32 0, ptr %poison_yet_again   ; Undefined behavior due to
                                           ; store to poison.

      store i32 %poison, ptr @g            ; Poison value stored to memory.
      %poison3 = load i32, ptr @g          ; Poison value loaded back from memory.

      %poison4 = load i16, ptr @g          ; Returns a poison value.
      %poison5 = load i64, ptr @g          ; Returns a poison value.

      %cmp = icmp slt i32 %poison, 0       ; Returns a poison value.
      br i1 %cmp, label %end, label %end   ; undefined behavior

    end:

<a id="well-defined-values"></a>

<a id="welldefinedvalues"></a>

### Well-Defined Values

Given a program execution, a value is *well defined* if the value does not have an undef bit and is not poison in the execution. An aggregate value or vector is well defined if its elements are well defined. The padding of an aggregate isn’t considered, since it isn’t visible without storing it into memory and loading it with a different type.

A constant of a [single value](type-system.md#t-single-value), non-vector type is well defined if it is neither ‘`undef`’ constant nor ‘`poison`’ constant. The result of [freeze instruction](instructions-other.md#i-freeze) is well defined regardless of its operand.

<a id="addresses-of-basic-blocks"></a>

<a id="blockaddress"></a>

### Addresses of Basic Blocks

`blockaddress(@function, %block)`

The ‘`blockaddress`’ constant computes the address of the specified basic block in the specified function.

It always has a `ptr addrspace(P)` type, where `P` is the address space of the function containing `%block` (usually `addrspace(0)`).

Taking the address of the entry block is illegal.

This value only has defined behavior when used as an operand to the ‘[indirectbr](instructions-terminators.md#i-indirectbr)’ or for comparisons against null. Pointer equality tests between label addresses results in undefined behavior — though, again, comparison against null is ok, and no label is equal to the null pointer. This may be passed around as an opaque pointer sized value as long as the bits are not inspected. This allows `ptrtoint` and arithmetic to be performed on these values so long as the original value is reconstituted before the `indirectbr` instruction.

Finally, some targets may provide defined semantics when using the value as the operand to an inline assembly, but that is target specific.

<a id="dso-local-equivalent"></a>

<a id="id6"></a>

### DSO Local Equivalent

`dso_local_equivalent @func`

A ‘`dso_local_equivalent`’ constant represents a function which is functionally equivalent to a given function, but is always defined in the current linkage unit. The resulting pointer has the same type as the underlying function. The resulting pointer is permitted, but not required, to be different from a pointer to the function, and it may have different values in different translation units.

The target function may not have `extern_weak` linkage.

`dso_local_equivalent` can be implemented as such:

- If the function has local linkage, hidden visibility, or is `dso_local`, `dso_local_equivalent` can be implemented as simply a pointer to the function.

- `dso_local_equivalent` can be implemented with a stub that tail-calls the function. Many targets support relocations that resolve at link time to either a function or a stub for it, depending on whether the function is defined within the linkage unit; LLVM will use this when available. (This is commonly called a “PLT stub”.) On other targets, the stub may need to be emitted explicitly.

This can be used wherever a `dso_local` instance of a function is needed without needing to explicitly make the original function `dso_local`. An instance where this can be used is for static offset calculations between a function and some other `dso_local` symbol. This is especially useful for the Relative VTables C++ ABI, where dynamic relocations for function pointers in VTables can be replaced with static relocations for offsets between the VTable and virtual functions which may not be `dso_local`.

This is currently only supported for ELF binary formats.

<a id="no-cfi"></a>

<a id="id7"></a>

### No CFI

`no_cfi @func`

With [Control-Flow Integrity (CFI)](https://clang.llvm.org/docs/ControlFlowIntegrity.html), a ‘`no_cfi`’ constant represents a function reference that does not get replaced with a reference to the CFI jump table in the `LowerTypeTests` pass. These constants may be useful in low-level programs, such as operating system kernels, which need to refer to the actual function body.

<a id="pointer-authentication-constants"></a>

<a id="ptrauth-constant"></a>

### Pointer Authentication Constants

`ptrauth (ptr CST, i32 KEY[, i64 DISC[, ptr ADDRDISC[, ptr DS]?]?]?)`

A ‘`ptrauth`’ constant represents a pointer with a cryptographic authentication signature embedded into some bits, as described in the [Pointer Authentication](PointerAuth.html) document.

A ‘`ptrauth`’ constant is simply a constant equivalent to the `llvm.ptrauth.sign` intrinsic, potentially fed by a discriminator `llvm.ptrauth.blend` if needed.

Its type is the same as the first argument. An integer constant discriminator and an address discriminator may be optionally specified. Otherwise, they have values `i64 0` and `ptr null`.

If the address discriminator is `null` then the expression is equivalent to

    %tmp = call i64 @llvm.ptrauth.sign(i64 ptrtoint (ptr CST to i64), i32 KEY, i64 DISC)
    %val = inttoptr i64 %tmp to ptr

Otherwise, the expression is equivalent to:

    %tmp1 = call i64 @llvm.ptrauth.blend(i64 ptrtoint (ptr ADDRDISC to i64), i64 DISC)
    %tmp2 = call i64 @llvm.ptrauth.sign(i64 ptrtoint (ptr CST to i64), i32 KEY, i64 %tmp1)
    %val = inttoptr i64 %tmp2 to ptr

If the deactivation symbol operand `DS` has a non-null value, the semantics are as if a [deactivation-symbol operand bundle](high-level-structure.md#deactivationsymbol) were added to the `llvm.ptrauth.sign` intrinsic calls above, with `DS` as the only operand.

<a id="constant-expressions"></a>

<a id="constantexprs"></a>

### Constant Expressions

Constant expressions are used to allow expressions involving other constants to be used as constants. Constant expressions may be of any [first class](type-system.md#t-firstclass) type and may involve any LLVM operation that does not have side effects (e.g., load and call are not supported). The following is the syntax for constant expressions:

`trunc (CST to TYPE)`  
Perform the [trunc operation](instructions-conversion.md#i-trunc) on constants.

`ptrtoint (CST to TYPE)`  
Perform the [ptrtoint operation](instructions-conversion.md#i-ptrtoint) on constants.

`ptrtoaddr (CST to TYPE)`  
Perform the [ptrtoaddr operation](instructions-conversion.md#i-ptrtoaddr) on constants.

`inttoptr (CST to TYPE)`  
Perform the [inttoptr operation](instructions-conversion.md#i-inttoptr) on constants. This one is *really* dangerous!

`bitcast (CST to TYPE)`  
Convert a constant, CST, to another TYPE. The constraints of the operands are the same as those for the [bitcast instruction](instructions-conversion.md#i-bitcast).

`addrspacecast (CST to TYPE)`  
Convert a constant pointer or constant vector of pointer, CST, to another TYPE in a different address space. The constraints of the operands are the same as those for the [addrspacecast instruction](instructions-conversion.md#i-addrspacecast).

`getelementptr (TY, CSTPTR, IDX0, IDX1, ...)`, `getelementptr inbounds (TY, CSTPTR, IDX0, IDX1, ...)`  
Perform the [getelementptr operation](instructions-memory.md#i-getelementptr) on constants. As with the [getelementptr](instructions-memory.md#i-getelementptr) instruction, the index list may have one or more indexes, which are required to make sense for the type of “pointer to TY”. These indexes may be implicitly sign-extended or truncated to match the index size of CSTPTR’s address space.

`extractelement (VAL, IDX)`  
Perform the [extractelement operation](instructions-vector-aggregate.md#i-extractelement) on constants.

`insertelement (VAL, ELT, IDX)`  
Perform the [insertelement operation](instructions-vector-aggregate.md#i-insertelement) on constants.

`shufflevector (VEC1, VEC2, IDXMASK)`  
Perform the [shufflevector operation](instructions-vector-aggregate.md#i-shufflevector) on constants.

`add (LHS, RHS)`  
Perform an addition on constants.

`sub (LHS, RHS)`  
Perform a subtraction on constants.

`xor (LHS, RHS)`  
Perform a bitwise xor on constants.

<a id="other-values"></a>

## Other Values

<a id="inline-assembler-expressions"></a>

<a id="inlineasmexprs"></a>

### Inline Assembler Expressions

LLVM supports inline assembler expressions (as opposed to [Module-Level Inline Assembly](high-level-structure.md#moduleasm)) through the use of a special value. This value represents the inline assembler as a template string (containing the instructions to emit), a list of operand constraints (stored as a string), a flag that indicates whether or not the inline asm expression has side effects, and a flag indicating whether the function containing the asm needs to align its stack conservatively.

The compiler may not assume that the actual code executed at runtime matches the contents of the template string. Correctness-critical analyses must base their results only on the list of operand constraints and the flags – not the contents of the template string. This ensures correct behavior if the assembly code emitted by this expression is altered later, e.g. via self-modifying code, as long as the code keeps upholding the requirements of the operand constraints and the flags.

The template string supports argument substitution of the operands using “`$`” followed by a number, to indicate substitution of the given register/memory location, as specified by the constraint string. “`${NUM:MODIFIER}`” may also be used, where `MODIFIER` is a target-specific annotation for how to print the operand (See [Asm template argument modifiers](#inline-asm-modifiers)).

A literal “`$`” may be included by using “`$$`” in the template. To include other special characters into the output, the usual “`\XX`” escapes may be used, just as in other strings. Note that after template substitution, the resulting assembly string is parsed by LLVM’s integrated assembler unless it is disabled – even when emitting a `.s` file – and thus must contain assembly syntax known to LLVM.

LLVM also supports a few more substitutions useful for writing inline assembly:

- `${:uid}`: Expands to a decimal integer unique to this inline assembly blob. This substitution is useful when declaring a local label. Many standard compiler optimizations, such as inlining, may duplicate an inline asm blob. Adding a blob-unique identifier ensures that the two labels will not conflict during assembly. This is used to implement [GCC’s %= special format string](https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html).

- `${:comment}`: Expands to the comment character of the current target’s assembly dialect. This is usually `#`, but many targets use other strings, such as `;`, `//`, or `!`.

- `${:private}`: Expands to the assembler private label prefix. Labels with this prefix will not appear in the symbol table of the assembled object. Typically the prefix is `L`, but targets may use other strings. `.L` is relatively popular.

LLVM’s support for inline asm is modeled closely on the requirements of Clang’s GCC-compatible inline-asm support. Thus, the feature-set and the constraint and modifier codes listed here are similar or identical to those in GCC’s inline asm support. However, to be clear, the syntax of the template and constraint strings described here is *not* the same as the syntax accepted by GCC and Clang, and, while most constraint letters are passed through as-is by Clang, some get translated to other codes when converting from the C source to the LLVM assembly.

An example inline assembler expression is:

    i32 (i32) asm "bswap $0", "=r,r"

Inline assembler expressions may **only** be used as the callee operand of a [call](instructions-other.md#i-call) or an [invoke](instructions-terminators.md#i-invoke) instruction. Thus, typically we have:

    %X = call i32 asm "bswap $0", "=r,r"(i32 %Y)

Inline asms with side effects not visible in the constraint list must be marked as having side effects. This is done through the use of the ‘`sideeffect`’ keyword, like so:

    call void asm sideeffect "eieio", ""()

In some cases inline asms will contain code that will not work unless the stack is aligned in some way, such as calls or SSE instructions on x86, yet will not contain code that does that alignment within the asm. The compiler should make conservative assumptions about what the asm might contain and should generate its usual stack alignment code in the prologue if the ‘`alignstack`’ keyword is present:

    call void asm alignstack "eieio", ""()

Inline asms also support using non-standard assembly dialects. The assumed dialect is ATT. When the ‘`inteldialect`’ keyword is present, the inline asm is using the Intel dialect. Currently, ATT and Intel are the only supported dialects. An example is:

    call void asm inteldialect "eieio", ""()

In the case that the inline asm might unwind the stack, the ‘`unwind`’ keyword must be used, so that the compiler emits unwinding information:

    call void asm unwind "call func", ""()

If the inline asm unwinds the stack and isn’t marked with the ‘`unwind`’ keyword, the behavior is undefined.

If multiple keywords appear, the ‘`sideeffect`’ keyword must come first, the ‘`alignstack`’ keyword second, the ‘`inteldialect`’ keyword third, and the ‘`unwind`’ keyword last.

<a id="inline-asm-constraint-string"></a>

#### Inline Asm Constraint String

The constraint list is a comma-separated string, each element containing one or more constraint codes.

For each element in the constraint list an appropriate register or memory operand will be chosen, and it will be made available to assembly template string expansion as `$0` for the first constraint in the list, `$1` for the second, etc.

There are three different types of constraints, which are distinguished by a prefix symbol in front of the constraint code: Output, Input, and Clobber. The constraints must always be given in that order: outputs first, then inputs, then clobbers. They cannot be intermingled.

There are also three different categories of constraint codes:

- Register constraint. This is either a register class, or a fixed physical register. This kind of constraint will allocate a register, and if necessary, bitcast the argument or result to the appropriate type.

- Memory constraint. This kind of constraint is for use with an instruction taking a memory operand. Different constraints allow for different addressing modes used by the target.

- Immediate value constraint. This kind of constraint is for an integer or other immediate value which can be rendered directly into an instruction. The various target-specific constraints allow the selection of a value in the proper range for the instruction you wish to use it with.

<a id="output-constraints"></a>

##### Output constraints

Output constraints are specified by an “`=`” prefix (e.g., “`=r`”). This indicates that the assembly will write to this operand, and the operand will then be made available as a return value of the `asm` expression. Output constraints do not consume an argument from the call instruction. (Except, see below about indirect outputs).

Normally, it is expected that no output locations are written to by the assembly expression until *all* of the inputs have been read. As such, LLVM may assign the same register to an output and an input. If this is not safe (e.g., if the assembly contains two instructions, where the first writes to one output, and the second reads an input and writes to a second output), then the “`&`” modifier must be used (e.g., “`=&r`”) to specify that the output is an “early-clobber” output. Marking an output as “early-clobber” ensures that LLVM will not use the same register for any inputs (other than an input tied to this output).

<a id="input-constraints"></a>

##### Input constraints

Input constraints do not have a prefix – just the constraint codes. Each input constraint will consume one argument from the call instruction. It is not permitted for the asm to write to any input register or memory location (unless that input is tied to an output). Note also that multiple inputs may all be assigned to the same register, if LLVM can determine that they necessarily all contain the same value.

Instead of providing a Constraint Code, input constraints may also “tie” themselves to an output constraint, by providing an integer as the constraint string. Tied inputs still consume an argument from the call instruction, and take up a position in the asm template numbering as is usual – they will simply be constrained to always use the same register as the output they’ve been tied to. For example, a constraint string of “`=r,0`” says to assign a register for output, and use that register as an input as well (it being the 0’th constraint).

It is permitted to tie an input to an “early-clobber” output. In that case, no *other* input may share the same register as the input tied to the early-clobber (even when the other input has the same value).

You may only tie an input to an output which has a register constraint, not a memory constraint. Only a single input may be tied to an output.

There is also an “interesting” feature which deserves a bit of explanation: if a register class constraint allocates a register which is too small for the value type operand provided as input, the input value will be split into multiple registers, and all of them passed to the inline asm.

However, this feature is often not as useful as you might think.

Firstly, the registers are *not* guaranteed to be consecutive. So, on those architectures that have instructions which operate on multiple consecutive instructions, this is not an appropriate way to support them. (e.g., the 32-bit SparcV8 has a 64-bit load, which instruction takes a single 32-bit register. The hardware then loads into both the named register, and the next register. This feature of inline asm would not be useful to support that.)

A few of the targets provide a template string modifier allowing explicit access to the second register of a two-register operand (e.g., MIPS `L`, `M`, and `D`). On such an architecture, you can actually access the second allocated register (yet, still, not any subsequent ones). But, in that case, you’re still probably better off simply splitting the value into two separate operands, for clarity. (e.g., see the description of the `A` constraint on X86, which, despite existing only for use with this feature, is not really a good idea to use)

<a id="indirect-inputs-and-outputs"></a>

##### Indirect inputs and outputs

Indirect output or input constraints can be specified by the “`*`” modifier (which goes after the “`=`” in case of an output). This indicates that the asm will write to or read from the contents of an *address* provided as an input argument. (Note that in this way, indirect outputs act more like an *input* than an output: just like an input, they consume an argument of the call expression, rather than producing a return value. An indirect output constraint is an “output” only in that the asm is expected to write to the contents of the input memory location, instead of just read from it).

This is most typically used for memory constraint, e.g., “`=*m`”, to pass the address of a variable as a value.

It is also possible to use an indirect *register* constraint, but only on output (e.g., “`=*r`”). This will cause LLVM to allocate a register for an output value normally, and then, separately emit a store to the address provided as input, after the provided inline asm. (It’s not clear what value this functionality provides, compared to writing the store explicitly after the asm statement, and it can only produce worse code, since it bypasses many optimization passes. I would recommend not using it.)

Call arguments for indirect constraints must have pointer type and must specify the [elementtype](high-level-structure.md#attr-elementtype) attribute to indicate the pointer element type.

<a id="clobber-constraints"></a>

##### Clobber constraints

A clobber constraint is indicated by a “`~`” prefix. A clobber does not consume an input operand, nor generate an output. Clobbers cannot use any of the general constraint code letters – they may use only explicit register constraints, e.g., “`~{eax}`”.

The one exception is that a clobber string of “`~{memory}`” indicates that the assembly reads and writes to arbitrary undeclared memory locations – not only the memory pointed to by a declared indirect output. Furthermore, the assembly may also cause synchronization with other threads, such as via release/acquire fences and atomic memory accesses.

Note that clobbering named registers that are also present in output constraints is not legal.

<a id="label-constraints"></a>

##### Label constraints

A label constraint is indicated by a “`!`” prefix and typically used in the form `"!i"`. Instead of consuming call arguments, label constraints consume indirect destination labels of `callbr` instructions.

Label constraints can only be used in conjunction with `callbr` and the number of label constraints must match the number of indirect destination labels in the `callbr` instruction.

<a id="constraint-codes"></a>

##### Constraint Codes

After a potential prefix comes constraint code, or codes.

A Constraint Code is either a single letter (e.g., “`r`”), a “`^`” character followed by two letters (e.g., “`^wc`”), or “`{`” register-name “`}`” (e.g., “`{eax}`”).

The one and two letter constraint codes are typically chosen to be the same as GCC’s constraint codes.

A single constraint may include one or more constraint codes in it, leaving it up to LLVM to choose which one to use. This is included mainly for compatibility with the translation of GCC inline asm coming from clang.

There are two ways to specify alternatives, and either or both may be used in an inline asm constraint list:

1.  Append the codes to each other, making a constraint code set. E.g. “`im`” or “`{eax}m`”. This means “choose any of the options in the set”. The choice of constraint is made independently for each constraint in the constraint list.

2.  Use “`|`” between constraint code sets, creating alternatives. Every constraint in the constraint list must have the same number of alternative sets. With this syntax, the same alternative in *all* of the items in the constraint list will be chosen together.

Putting those together, you might have a two operand constraint string like `"rm|r,ri|rm"`. This indicates that if operand 0 is `r` or `m`, then operand 1 may be one of `r` or `i`. If operand 0 is `r`, then operand 1 may be one of `r` or `m`. But, operand 0 and 1 cannot both be of type m.

However, the use of either of the alternatives features is *NOT* recommended, as LLVM is not able to make an intelligent choice about which one to use. (At the point it currently needs to choose, not enough information is available to do so in a smart way.) Thus, it simply tries to make a choice that’s most likely to compile, not one that will be optimal performance. (e.g., given “`rm`”, it’ll always choose to use memory, not registers). And, if given multiple registers, or multiple register classes, it will simply choose the first one. (In fact, it doesn’t currently even ensure explicitly specified physical registers are unique, so specifying multiple physical registers as alternatives, like `{r11}{r12},{r11}{r12}`, will assign r11 to both operands, not at all what was intended.)

<a id="supported-constraint-code-list"></a>

##### Supported Constraint Code List

The constraint codes are, in general, expected to behave the same way they do in GCC. LLVM’s support is often implemented on an ‘as-needed’ basis, to support C inline asm code which was supported by GCC. A mismatch in behavior between LLVM and GCC likely indicates a bug in LLVM.

Some constraint codes are typically supported by all targets:

- `r`: A register in the target’s general purpose register class.

- `m`: A memory address operand. It is target-specific what addressing modes are supported, typical examples are register, or register + register offset, or register + immediate offset (of some target-specific size).

- `p`: An address operand. Similar to `m`, but used by “load address” type instructions without touching memory.

- `i`: An integer constant (of target-specific width). Allows either a simple immediate, or a relocatable value.

- `n`: An integer constant – *not* including relocatable values.

- `s`: A symbol or label reference with a constant offset.

- `X`: Allows an operand of any kind, no constraint whatsoever. Typically useful to pass a label for an asm branch or call.

- `{register-name}`: Requires exactly the named physical register.

Other constraints are target-specific:

AArch64:

- `z`: An immediate integer 0. Outputs `WZR` or `XZR`, as appropriate.

- `I`: An immediate integer valid for an `ADD` or `SUB` instruction, i.e., 0 to 4095 with optional shift by 12.

- `J`: An immediate integer that, when negated, is valid for an `ADD` or `SUB` instruction, i.e., -1 to -4095 with optional left shift by 12.

- `K`: An immediate integer that is valid for the ‘bitmask immediate 32’ of a logical instruction like `AND`, `EOR`, or `ORR` with a 32-bit register.

- `L`: An immediate integer that is valid for the ‘bitmask immediate 64’ of a logical instruction like `AND`, `EOR`, or `ORR` with a 64-bit register.

- `M`: An immediate integer for use with the `MOV` assembly alias on a 32-bit register. This is a superset of `K`: in addition to the bitmask immediate, also allows immediate integers which can be loaded with a single `MOVZ` or `MOVL` instruction.

- `N`: An immediate integer for use with the `MOV` assembly alias on a 64-bit register. This is a superset of `L`.

- `Q`: Memory address operand must be in a single register (no offsets). (However, LLVM currently does this for the `m` constraint as well.)

- `r`: A 32 or 64-bit integer register (W\* or X\*).

- `S`: A symbol or label reference with a constant offset. The generic `s` is not supported.

- `Uci`: Like r, but restricted to registers 8 to 11 inclusive.

- `Ucj`: Like r, but restricted to registers 12 to 15 inclusive.

- `w`: A 32, 64, or 128-bit floating-point, SIMD or SVE vector register.

- `x`: Like w, but restricted to registers 0 to 15 inclusive.

- `y`: Like w, but restricted to SVE vector registers Z0 to Z7 inclusive.

- `Uph`: One of the upper eight SVE predicate registers (P8 to P15)

- `Upl`: One of the lower eight SVE predicate registers (P0 to P7)

- `Upa`: Any of the SVE predicate registers (P0 to P15)

AMDGPU:

- `r`: A 32 or 64-bit integer register.

- `s`: SGPR register or tuple

- `v`: VGPR register or tuple

- `a`: AGPR register or tuple. Only valid on gfx908+.

- `VA`: VGPR or AGPR register or tuple. Only valid on gfx90a+.

- `v[0-9]`: The 32-bit VGPR register, number 0-9.

- `s[0-9]`: The 32-bit SGPR register, number 0-9.

- `a[0-9]`: The 32-bit AGPR register, number 0-9.

- `I`: An integer inline constant in the range from -16 to 64.

- `J`: A 16-bit signed integer constant.

- `A`: An integer or a floating-point inline constant.

- `B`: A 32-bit signed integer constant.

- `C`: A 32-bit unsigned integer constant or an integer inline constant in the range from -16 to 64.

- `DA`: A 64-bit constant that can be split into two “A” constants.

- `DB`: A 64-bit constant that can be split into two “B” constants.

All ARM modes:

- `Q`, `Um`, `Un`, `Uq`, `Us`, `Ut`, `Uv`, `Uy`: Memory address operand. Treated the same as operand `m`, at the moment.

- `Te`: An even general-purpose 32-bit integer register: `r0,r2,...,r12,r14`

- `To`: An odd general-purpose 32-bit integer register: `r1,r3,...,r11`

ARM and ARM’s Thumb2 mode:

- `j`: An immediate integer between 0 and 65535 (valid for `MOVW`)

- `I`: An immediate integer valid for a data-processing instruction.

- `J`: An immediate integer between -4095 and 4095.

- `K`: An immediate integer whose bitwise inverse is valid for a data-processing instruction. (Can be used with template modifier “`B`” to print the inverted value).

- `L`: An immediate integer whose negation is valid for a data-processing instruction. (Can be used with template modifier “`n`” to print the negated value).

- `M`: A power of two or an integer between 0 and 32.

- `N`: Invalid immediate constraint.

- `O`: Invalid immediate constraint.

- `r`: A general-purpose 32-bit integer register (`r0-r15`).

- `l`: In Thumb2 mode, low 32-bit GPR registers (`r0-r7`). In ARM mode, same as `r`.

- `h`: In Thumb2 mode, a high 32-bit GPR register (`r8-r15`). In ARM mode, invalid.

- `w`: A 32, 64, or 128-bit floating-point/SIMD register in the ranges `s0-s31`, `d0-d31`, or `q0-q15`, respectively.

- `t`: A 32, 64, or 128-bit floating-point/SIMD register in the ranges `s0-s31`, `d0-d15`, or `q0-q7`, respectively.

- `x`: A 32, 64, or 128-bit floating-point/SIMD register in the ranges `s0-s15`, `d0-d7`, or `q0-q3`, respectively.

ARM’s Thumb1 mode:

- `I`: An immediate integer between 0 and 255.

- `J`: An immediate integer between -255 and -1.

- `K`: An immediate integer between 0 and 255, with optional left-shift by some amount.

- `L`: An immediate integer between -7 and 7.

- `M`: An immediate integer which is a multiple of 4 between 0 and 1020.

- `N`: An immediate integer between 0 and 31.

- `O`: An immediate integer which is a multiple of 4 between -508 and 508.

- `r`: A low 32-bit GPR register (`r0-r7`).

- `l`: A low 32-bit GPR register (`r0-r7`).

- `h`: A high GPR register (`r0-r7`).

- `w`: A 32, 64, or 128-bit floating-point/SIMD register in the ranges `s0-s31`, `d0-d31`, or `q0-q15`, respectively.

- `t`: A 32, 64, or 128-bit floating-point/SIMD register in the ranges `s0-s31`, `d0-d15`, or `q0-q7`, respectively.

- `x`: A 32, 64, or 128-bit floating-point/SIMD register in the ranges `s0-s15`, `d0-d7`, or `q0-q3`, respectively.

Hexagon:

- `o`, `v`: A memory address operand, treated the same as constraint `m`, at the moment.

- `r`: A 32 or 64-bit register.

LoongArch:

- `f`: A floating-point register (if available).

- `k`: A memory operand whose address is formed by a base register and (optionally scaled) index register.

- `l`: A signed 16-bit constant.

- `m`: A memory operand whose address is formed by a base register and offset that is suitable for use in instructions with the same addressing mode as st.w and ld.w.

- `q`: A general-purpose register except for \$r0 and \$r1 (for the csrxchg instruction).

- `I`: A signed 12-bit constant (for arithmetic instructions).

- `J`: An immediate integer zero.

- `K`: An unsigned 12-bit constant (for logic instructions).

- `ZB`: An address that is held in a general-purpose register. The offset is zero.

- `ZC`: A memory operand whose address is formed by a base register and offset that is suitable for use in instructions with the same addressing mode as ll.w and sc.w.

MSP430:

- `r`: An 8 or 16-bit register.

MIPS:

- `I`: An immediate signed 16-bit integer.

- `J`: An immediate integer zero.

- `K`: An immediate unsigned 16-bit integer.

- `L`: An immediate 32-bit integer, where the lower 16 bits are 0.

- `N`: An immediate integer between -65535 and -1.

- `O`: An immediate signed 15-bit integer.

- `P`: An immediate integer between 1 and 65535.

- `m`: A memory address operand. In MIPS-SE mode, allows a base address register plus 16-bit immediate offset. In MIPS mode, just a base register.

- `R`: A memory address operand. In MIPS-SE mode, allows a base address register plus a 9-bit signed offset. In MIPS mode, the same as constraint `m`.

- `ZC`: A memory address operand, suitable for use in a `pref`, `ll`, or `sc` instruction on the given subtarget (details vary).

- `r`, `d`, `y`: A 32 or 64-bit GPR register.

- `f`: A 32 or 64-bit FPU register (`F0-F31`), or a 128-bit MSA register (`W0-W31`). In the case of MSA registers, it is recommended to use the `w` argument modifier for compatibility with GCC.

- `c`: A 32-bit or 64-bit GPR register suitable for indirect jump (always `25`).

- `l`: The `lo` register, 32 or 64-bit.

- `x`: Invalid.

NVPTX:

- `b`: A 1-bit integer register.

- `c` or `h`: A 16-bit integer register.

- `r`: A 32-bit integer register.

- `l` or `N`: A 64-bit integer register.

- `q`: A 128-bit integer register.

- `f`: A 32-bit float register.

- `d`: A 64-bit float register.

PowerPC:

- `I`: An immediate signed 16-bit integer.

- `J`: An immediate unsigned 16-bit integer, shifted left 16 bits.

- `K`: An immediate unsigned 16-bit integer.

- `L`: An immediate signed 16-bit integer, shifted left 16 bits.

- `M`: An immediate integer greater than 31.

- `N`: An immediate integer that is an exact power of 2.

- `O`: The immediate integer constant 0.

- `P`: An immediate integer constant whose negation is a signed 16-bit constant.

- `es`, `o`, `Q`, `Z`, `Zy`: A memory address operand, currently treated the same as `m`.

- `r`: A 32 or 64-bit integer register.

- `b`: A 32 or 64-bit integer register, excluding `R0` (that is: `R1-R31`).

- `f`: A 32 or 64-bit float register (`F0-F31`),

- `v`: For `4 x f32` or `4 x f64` types, a 128-bit altivec vector  
  register (`V0-V31`).

- `y`: Condition register (`CR0-CR7`).

- `wc`: An individual CR bit in a CR register.

- `wa`, `wd`, `wf`: Any 128-bit VSX vector register, from the full VSX register set (overlapping both the floating-point and vector register files).

- `ws`: A 32 or 64-bit floating-point register, from the full VSX register set.

RISC-V:

- `A`: An address operand (using a general-purpose register, without an offset).

- `I`: A 12-bit signed integer immediate operand.

- `J`: A zero integer immediate operand.

- `K`: A 5-bit unsigned integer immediate operand.

- `f`: A 32- or 64-bit floating-point register (requires F or D extension).

- `r`: A 32- or 64-bit general-purpose register (depending on the platform `XLEN`).

- `S`: Alias for `s`.

- `vd`: A vector register, excluding `v0` (requires V extension).

- `vm`: The vector register `v0` (requires V extension).

- `vr`: A vector register (requires V extension).

Sparc:

- `I`: An immediate 13-bit signed integer.

- `r`: A 32-bit integer register.

- `f`: Any floating-point register on SparcV8, or a floating-point register in the “low” half of the registers on SparcV9.

- `e`: Any floating-point register. (Same as `f` on SparcV8.)

SystemZ:

- `I`: An immediate unsigned 8-bit integer.

- `J`: An immediate unsigned 12-bit integer.

- `K`: An immediate signed 16-bit integer.

- `L`: An immediate signed 20-bit integer.

- `M`: An immediate integer 0x7fffffff.

- `Q`: A memory address operand with a base address and a 12-bit immediate unsigned displacement.

- `R`: A memory address operand with a base address, a 12-bit immediate unsigned displacement, and an index register.

- `S`: A memory address operand with a base address and a 20-bit immediate signed displacement.

- `T`: A memory address operand with a base address, a 20-bit immediate signed displacement, and an index register.

- `r` or `d`: A 32, 64, or 128-bit integer register.

- `a`: A 32, 64, or 128-bit integer address register (excludes R0, which in an address context evaluates as zero).

- `h`: A 32-bit value in the high part of a 64bit data register (LLVM-specific)

- `f`: A 16, 32, 64, or 128-bit floating-point register.

X86:

- `I`: An immediate integer between 0 and 31.

- `J`: An immediate integer between 0 and 64.

- `K`: An immediate signed 8-bit integer.

- `L`: An immediate integer, 0xff or 0xffff or (in 64-bit mode only) 0xffffffff.

- `M`: An immediate integer between 0 and 3.

- `N`: An immediate unsigned 8-bit integer.

- `O`: An immediate integer between 0 and 127.

- `e`: An immediate 32-bit signed integer.

- `Z`: An immediate 32-bit unsigned integer.

- `q`: An 8, 16, 32, or 64-bit register which can be accessed as an 8-bit `l` integer register. On X86-32, this is the `a`, `b`, `c`, and `d` registers, and on X86-64, it is all of the integer registers. When feature `egpr` and `inline-asm-use-gpr32` are both on, it will be extended to gpr32.

- `Q`: An 8, 16, 32, or 64-bit register which can be accessed as an 8-bit `h` integer register. This is the `a`, `b`, `c`, and `d` registers.

- `r` or `l`: An 8, 16, 32, or 64-bit integer register. When feature `egpr` and `inline-asm-use-gpr32` are both on, it will be extended to gpr32.

- `R`: An 8, 16, 32, or 64-bit “legacy” integer register – one which has existed since i386, and can be accessed without the REX prefix.

- `f`: A 32, 64, or 80-bit ‘387 FPU stack pseudo-register.

- `y`: A 64-bit MMX register, if MMX is enabled.

- `v`: If SSE is enabled: a 32 or 64-bit scalar operand, or 128-bit vector operand in a SSE register. If AVX is also enabled, can also be a 256-bit vector operand in an AVX register. If AVX-512 is also enabled, can also be a 512-bit vector operand in an AVX512 register. Otherwise, an error.

- `Ws`: A symbolic reference with an optional constant addend or a label reference.

- `x`: The same as `v`, except that when AVX-512 is enabled, the `x` code only allocates into the first 16 AVX-512 registers, while the `v` code allocates into any of the 32 AVX-512 registers.

- `Y`: The same as `x`, if *SSE2* is enabled, otherwise an error.

- `A`: Special case: allocates EAX first, then EDX, for a single operand (in 32-bit mode, a 64-bit integer operand will get split into two registers). It is not recommended to use this constraint, as in 64-bit mode, the 64-bit operand will get allocated only to RAX – if two 32-bit operands are needed, you’re better off splitting it yourself, before passing it to the asm statement.

- `jr`: An 8, 16, 32, or 64-bit integer gpr16. It won’t be extended to gpr32 when feature `egpr` or `inline-asm-use-gpr32` is on.

- `jR`: An 8, 16, 32, or 64-bit integer gpr32 when feature `egpr` is on. Otherwise, same as `r`.

XCore:

- `r`: A 32-bit integer register.

<a id="asm-template-argument-modifiers"></a>

<a id="inline-asm-modifiers"></a>

#### Asm template argument modifiers

In the asm template string, modifiers can be used on the operand reference, like “`${0:n}`”.

The modifiers are, in general, expected to behave the same way they do in GCC. LLVM’s support is often implemented on an ‘as-needed’ basis, to support C inline asm code which was supported by GCC. A mismatch in behavior between LLVM and GCC likely indicates a bug in LLVM.

Target-independent:

- `a`: Print a memory reference. Targets might customize the output.

- `c`: Print an immediate integer constant unadorned, without the target-specific immediate punctuation (e.g., no `$` prefix).

- `n`: Negate and print immediate integer constant unadorned, without the target-specific immediate punctuation (e.g., no `$` prefix).

- `l`: Print as an unadorned label, without the target-specific label punctuation (e.g., no `$` prefix).

AArch64:

- `w`: Print a GPR register with a `w*` name instead of `x*` name. E.g., instead of `x30`, print `w30`.

- `x`: Print a GPR register with a `x*` name. (this is the default, anyhow).

- `b`, `h`, `s`, `d`, `q`: Print a floating-point/SIMD register with a `b*`, `h*`, `s*`, `d*`, or `q*` name, rather than the default of `v*`.

AMDGPU:

- `r`: No effect.

ARM:

- `a`: Print an operand as an address (with `[` and `]` surrounding a register).

- `P`: No effect.

- `q`: No effect.

- `y`: Print a VFP single-precision register as an indexed double (e.g., print as `d4[1]` instead of `s9`)

- `B`: Bitwise invert and print an immediate integer constant without `#` prefix.

- `L`: Print the low 16-bits of an immediate integer constant.

- `M`: Print as a register set suitable for ldm/stm. Also prints *all* register operands subsequent to the specified one (!), so use carefully.

- `Q`: Print the low-order register of a register-pair, or the low-order register of a two-register operand.

- `R`: Print the high-order register of a register-pair, or the high-order register of a two-register operand.

- `H`: Print the second register of a register-pair. (On a big-endian system, `H` is equivalent to `Q`, and on little-endian system, `H` is equivalent to `R`.)

- `e`: Print the low doubleword register of a NEON quad register.

- `f`: Print the high doubleword register of a NEON quad register.

- `m`: Print the base register of a memory operand without the `[` and `]` adornment.

Hexagon:

- `L`: Print the second register of a two-register operand. Requires that it has been allocated consecutively to the first.

- `I`: Print the letter ‘i’ if the operand is an integer constant, otherwise nothing. Used to print ‘addi’ vs ‘add’ instructions.

LoongArch:

- `u`: Print an LASX register.

- `w`: Print an LSX register.

- `z`: Print \$zero register if operand is zero, otherwise print it normally.

MSP430:

No additional modifiers.

MIPS:

- `X`: Print an immediate integer as hexadecimal

- `x`: Print the low 16 bits of an immediate integer as hexadecimal.

- `d`: Print an immediate integer as decimal.

- `m`: Subtract one and print an immediate integer as decimal.

- `z`: Print \$0 if an immediate zero, otherwise print normally.

- `L`: Print the low-order register of a two-register operand, or prints the address of the low-order word of a double-word memory operand.

- `M`: Print the high-order register of a two-register operand, or prints the address of the high-order word of a double-word memory operand.

- `D`: Print the second register of a two-register operand, or prints the second word of a double-word memory operand. (On a big-endian system, `D` is equivalent to `L`, and on little-endian system, `D` is equivalent to `M`.)

- `w`: No effect. Provided for compatibility with GCC which requires this modifier in order to print MSA registers (`W0-W31`) with the `f` constraint.

NVPTX:

- `r`: No effect.

PowerPC:

- `L`: Print the second register of a two-register operand. Requires that it has been allocated consecutively to the first.

- `I`: Print the letter ‘i’ if the operand is an integer constant, otherwise nothing. Used to print ‘addi’ vs ‘add’ instructions.

- `y`: For a memory operand, prints formatter for a two-register X-form instruction. (Currently always prints `r0,OPERAND`).

- `U`: Prints ‘u’ if the memory operand is an update form, and nothing otherwise. (NOTE: LLVM does not support update form, so this will currently always print nothing)

- `X`: Prints ‘x’ if the memory operand is an indexed form. (NOTE: LLVM does not support indexed form, so this will currently always print nothing)

RISC-V:

- `i`: Print the letter ‘i’ if the operand is not a register, otherwise print nothing. Used to print ‘addi’ vs ‘add’ instructions, etc.

- `z`: Print the register `zero` if an immediate zero, otherwise print normally.

Sparc:

- `L`: Print the low-order register of a two-register operand.

- `H`: Print the high-order register of a two-register operand.

- `r`: No effect.

SystemZ:

SystemZ implements only `n`, and does *not* support any of the other target-independent modifiers.

X86:

- `a`: Print a memory reference. This displays as `sym(%rip)` for x86-64. i386 should only use this with the static relocation model.

- `c`: Print an unadorned integer or symbol name. (The latter is target-specific behavior for this typically target-independent modifier).

- `A`: Print a register name with a ‘`*`’ before it.

- `b`: Print an 8-bit register name (e.g., `al`); do nothing on a memory operand.

- `h`: Print the upper 8-bit register name (e.g., `ah`); do nothing on a memory operand.

- `w`: Print the 16-bit register name (e.g., `ax`); do nothing on a memory operand.

- `k`: Print the 32-bit register name (e.g., `eax`); do nothing on a memory operand.

- `q`: Print the 64-bit register name (e.g., `rax`), if 64-bit registers are available, otherwise the 32-bit register name; do nothing on a memory operand.

- `n`: Negate and print an unadorned integer, or, for operands other than an immediate integer (e.g., a relocatable symbol expression), print a ‘-’ before the operand. (The behavior for relocatable symbol expressions is a target-specific behavior for this typically target-independent modifier)

- `H`: Print a memory reference with additional offset +8.

- `p`: Print a raw symbol name (without syntax-specific prefixes).

- `P`: Print a memory reference used as the argument of a call instruction or used with explicit base reg and index reg as its offset. So it can not use additional regs to present the memory reference. (E.g. omit `(rip)`, even though it’s PC-relative.)

XCore:

No additional modifiers.

<a id="inline-asm-metadata"></a>

#### Inline Asm Metadata

The call instructions that wrap inline asm nodes may have a “`!srcloc`” MDNode attached to it that contains a list of constant integers. If present, the code generator will use the integer as the location cookie value when reporting errors through the `LLVMContext` error reporting mechanisms. This allows a front-end to correlate backend errors that occur with inline asm back to the source code that produced it. For example:

    call void asm sideeffect "something bad", ""(), !srcloc !42
    ...
    !42 = !{ i64 1234567 }

It is up to the front-end to make sense of the magic numbers it places in the IR. If the MDNode contains multiple constants, the code generator will use the one that corresponds to the line of the asm that the error occurs on.
