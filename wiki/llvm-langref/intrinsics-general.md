[Wiki](../index.md) › [LLVM LangRef](index.md)

# Intrinsics: general and miscellaneous

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="convergence-intrinsics"></a>

### Convergence Intrinsics

The LLVM convergence intrinsics for controlling the semantics of `convergent` operations, which all start with the `llvm.experimental.convergence.` prefix, are described in the [Convergent Operation Semantics](ConvergentOperations.html) document.

<a id="debugger-intrinsics"></a>

<a id="dbg-intrinsics"></a>

### Debugger Intrinsics

The LLVM debugger intrinsics (which all start with `llvm.dbg.` prefix), are described in the [LLVM Source Level Debugging](SourceLevelDebugging.html#format-common-intrinsics) document.

<a id="exception-handling-intrinsics"></a>

### Exception Handling Intrinsics

The LLVM exception handling intrinsics (which all start with `llvm.eh.` prefix), are described in the [LLVM Exception Handling](ExceptionHandling.html#exception-handling-intrinsics) document.

<a id="pointer-authentication-intrinsics"></a>

### Pointer Authentication Intrinsics

The LLVM pointer authentication intrinsics (which all start with `llvm.ptrauth.` prefix), are described in the [Pointer Authentication](PointerAuth.html#intrinsics) document.

<a id="trampoline-intrinsics"></a>

<a id="int-trampoline"></a>

### Trampoline Intrinsics

These intrinsics make it possible to excise one parameter, marked with the [nest](high-level-structure.md#nest) attribute, from a function. The result is a callable function pointer lacking the nest parameter - the caller does not need to provide a value for it. Instead, the value to use is stored in advance in a “trampoline”, a block of memory usually allocated on the stack, which also contains code to splice the nest value into the argument list. This is used to implement the GCC nested function address extension.

For example, if the function is `i32 f(ptr nest %c, i32 %x, i32 %y)` then the resulting function pointer has signature `i32 (i32, i32)`. It can be created as follows:

    %tramp = alloca [10 x i8], align 4 ; size and alignment only correct for X86
    call ptr @llvm.init.trampoline(ptr %tramp, ptr @f, ptr %nval)
    %fp = call ptr @llvm.adjust.trampoline(ptr %tramp)

The call `%val = call i32 %fp(i32 %x, i32 %y)` is then equivalent to `%val = call i32 %f(ptr %nval, i32 %x, i32 %y)`.

<a id="llvm-init-trampoline-intrinsic"></a>

<a id="int-it"></a>

#### ‘`llvm.init.trampoline`’ Intrinsic

<a id="id1055"></a>

##### Syntax:

    declare void @llvm.init.trampoline(ptr <tramp>, ptr <func>, ptr <nval>)

<a id="id1056"></a>

##### Overview:

This fills the memory pointed to by `tramp` with executable code, turning it into a trampoline.

<a id="id1057"></a>

##### Arguments:

The `llvm.init.trampoline` intrinsic takes three arguments, all pointers. The `tramp` argument must point to a sufficiently large and sufficiently aligned block of memory; this memory is written to by the intrinsic. Note that the size and the alignment are target-specific - LLVM currently provides no portable way of determining them, so a front-end that generates this intrinsic needs to have some target-specific knowledge.

The `func` argument must be a constant (potentially bitcasted) pointer to a function declaration or definition, since the calling convention may affect the content of the trampoline that is created.

<a id="id1058"></a>

##### Semantics:

The block of memory pointed to by `tramp` is filled with target dependent code, turning it into a function. Then `tramp` needs to be passed to [llvm.adjust.trampoline](#int-at) to get a pointer which can be [bitcast (to a new function) and called](#int-trampoline). The new function’s signature is the same as that of `func` with any arguments marked with the `nest` attribute removed. At most one such `nest` argument is allowed, and it must be of pointer type. Calling the new function is equivalent to calling `func` with the same argument list, but with `nval` used for the missing `nest` argument. If, after calling `llvm.init.trampoline`, the memory pointed to by `tramp` is modified, then the effect of any later call to the returned function pointer is undefined.

<a id="llvm-adjust-trampoline-intrinsic"></a>

<a id="int-at"></a>

#### ‘`llvm.adjust.trampoline`’ Intrinsic

<a id="id1059"></a>

##### Syntax:

    declare ptr @llvm.adjust.trampoline(ptr <tramp>)

<a id="id1060"></a>

##### Overview:

This performs any required machine-specific adjustment to the address of a trampoline (passed as `tramp`).

<a id="id1061"></a>

##### Arguments:

`tramp` must point to a block of memory which already has trampoline code filled in by a previous call to [llvm.init.trampoline](#int-it).

<a id="id1062"></a>

##### Semantics:

On some architectures the address of the code to be executed needs to be different than the address where the trampoline is actually stored. This intrinsic returns the executable address corresponding to `tramp` after performing the required machine-specific adjustments. The pointer returned can then be [bitcast and executed](#int-trampoline).

<a id="memory-use-markers"></a>

### Memory Use Markers

This class of intrinsics provides information about the [lifetime of allocated objects](high-level-structure.md#objectlifetime) and ranges where variables are immutable.

<a id="llvm-lifetime-start-intrinsic"></a>

<a id="int-lifestart"></a>

#### ‘`llvm.lifetime.start`’ Intrinsic

<a id="id1571"></a>

##### Syntax:

    declare void @llvm.lifetime.start(ptr captures(none) <ptr>)

<a id="id1572"></a>

##### Overview:

The ‘`llvm.lifetime.start`’ intrinsic specifies the start of a memory object’s lifetime.

<a id="id1573"></a>

##### Arguments:

The argument is either a `poison` value or an SSA variable whose defining instruction is `alloca` or a call of the `llvm.structured.alloca` intrinsics. Otherwise, the IR is considered ill-formed.

<a id="id1574"></a>

##### Semantics:

If `ptr` is a `poison` value, the intrinsic has no effect.

Otherwise, the stack-allocated object that `ptr` points to is initially marked as dead. After ‘`llvm.lifetime.start`’, the stack object is marked as alive and has an uninitialized value. Calling `llvm.lifetime.start` when the stack object is already alive just resets its contents to be uninitialized.

The stack object is marked as dead again when either [llvm.lifetime.end](#int-lifeend) to the alloca/structured.alloca is executed or the function returns. After [llvm.lifetime.end](#int-lifeend) is called, ‘`llvm.lifetime.start`’ on the stack object can be called again. The second ‘`llvm.lifetime.start`’ call marks the object as alive, but it does not change the address of the object.

<a id="llvm-lifetime-end-intrinsic"></a>

<a id="int-lifeend"></a>

#### ‘`llvm.lifetime.end`’ Intrinsic

<a id="id1575"></a>

##### Syntax:

    declare void @llvm.lifetime.end(ptr captures(none) <ptr>)

<a id="id1576"></a>

##### Overview:

The ‘`llvm.lifetime.end`’ intrinsic specifies the end of a [allocated object’s lifetime](high-level-structure.md#objectlifetime).

<a id="id1577"></a>

##### Arguments:

The argument is either a `poison` value or an SSA variable whose defining instruction is `alloca` or a call of the `llvm.structured.alloca` intrinsics. Otherwise, the IR is considered ill-formed.

<a id="id1578"></a>

##### Semantics:

If `ptr` is a `poison` value, the intrinsic has no effect.

Otherwise, the stack-allocated object that `ptr` points to becomes dead after the call to this intrinsic.

Calling `llvm.lifetime.end` on an already dead alloca/structured.alloca is no-op.

<a id="llvm-invariant-start-intrinsic"></a>

#### ‘`llvm.invariant.start`’ Intrinsic

<a id="id1579"></a>

##### Syntax:

This is an overloaded intrinsic. The [allocated object](high-level-structure.md#allocatedobjects) can belong to any address space.

    declare ptr @llvm.invariant.start.p0(i64 <size>, ptr captures(none) <ptr>)

<a id="id1580"></a>

##### Overview:

The ‘`llvm.invariant.start`’ intrinsic specifies that the contents of an [allocated object](high-level-structure.md#allocatedobjects) will not change.

<a id="id1581"></a>

##### Arguments:

The first argument is a constant integer representing the size of the object, or -1 if it is variable sized. The second argument is a pointer to the object.

<a id="id1582"></a>

##### Semantics:

This intrinsic indicates that until an `llvm.invariant.end` that uses the return value, the referenced memory location is constant and unchanging.

<a id="llvm-invariant-end-intrinsic"></a>

#### ‘`llvm.invariant.end`’ Intrinsic

<a id="id1583"></a>

##### Syntax:

This is an overloaded intrinsic. The [allocated object](high-level-structure.md#allocatedobjects) can belong to any address space.

    declare void @llvm.invariant.end.p0(ptr <start>, i64 <size>, ptr captures(none) <ptr>)

<a id="id1584"></a>

##### Overview:

The ‘`llvm.invariant.end`’ intrinsic specifies that the contents of an [allocated object](high-level-structure.md#allocatedobjects) are mutable.

<a id="id1585"></a>

##### Arguments:

The first argument is the matching `llvm.invariant.start` intrinsic. The second argument is a constant integer representing the size of the object, or -1 if it is variable sized and the third argument is a pointer to the object.

<a id="id1586"></a>

##### Semantics:

This intrinsic indicates that the memory is mutable again.

<a id="llvm-launder-invariant-group-intrinsic"></a>

#### ‘`llvm.launder.invariant.group`’ Intrinsic

<a id="id1587"></a>

##### Syntax:

This is an overloaded intrinsic. The [allocated object](high-level-structure.md#allocatedobjects) can belong to any address space. The returned pointer must belong to the same address space as the argument.

    declare ptr @llvm.launder.invariant.group.p0(ptr <ptr>)

<a id="id1588"></a>

##### Overview:

The ‘`llvm.launder.invariant.group`’ intrinsic can be used when an invariant established by `invariant.group` metadata no longer holds, to obtain a new pointer value that carries fresh invariant group information. It is an experimental intrinsic, which means that its semantics might change in the future.

<a id="id1589"></a>

##### Arguments:

The `llvm.launder.invariant.group` takes only one argument, which is a pointer to the memory.

<a id="id1590"></a>

##### Semantics:

Returns another pointer that aliases its argument but which is considered different for the purposes of `load`/`store` `invariant.group` metadata. It does not read any accessible memory and the execution can be speculated.

<a id="llvm-strip-invariant-group-intrinsic"></a>

#### ‘`llvm.strip.invariant.group`’ Intrinsic

<a id="id1591"></a>

##### Syntax:

This is an overloaded intrinsic. The [allocated object](high-level-structure.md#allocatedobjects) can belong to any address space. The returned pointer must belong to the same address space as the argument.

    declare ptr @llvm.strip.invariant.group.p0(ptr <ptr>)

<a id="id1592"></a>

##### Overview:

The ‘`llvm.strip.invariant.group`’ intrinsic can be used when an invariant established by `invariant.group` metadata no longer holds, to obtain a new pointer value that does not carry the invariant information. It is an experimental intrinsic, which means that its semantics might change in the future.

<a id="id1593"></a>

##### Arguments:

The `llvm.strip.invariant.group` takes only one argument, which is a pointer to the memory.

<a id="id1594"></a>

##### Semantics:

Returns another pointer that aliases its argument but which has no associated `invariant.group` metadata. It does not read any memory and can be speculated.

<a id="general-intrinsics"></a>

### General Intrinsics

This class of intrinsics is designed to be generic and has no specific purpose.

<a id="llvm-var-annotation-intrinsic"></a>

#### ‘`llvm.var.annotation`’ Intrinsic

<a id="id1824"></a>

##### Syntax:

    declare void @llvm.var.annotation(ptr <val>, ptr <str>, ptr <str>, i32  <int>)

<a id="id1825"></a>

##### Overview:

The ‘`llvm.var.annotation`’ intrinsic.

<a id="id1826"></a>

##### Arguments:

The first argument is a pointer to a value, the second is a pointer to a global string, the third is a pointer to a global string which is the source file name, and the last argument is the line number.

<a id="id1827"></a>

##### Semantics:

This intrinsic allows annotation of local variables with arbitrary strings. This can be useful for special purpose optimizations that want to look for these annotations. These have no other defined use; they are ignored by code generation and optimization.

<a id="llvm-ptr-annotation-intrinsic"></a>

#### ‘`llvm.ptr.annotation.*`’ Intrinsic

<a id="id1828"></a>

##### Syntax:

This is an overloaded intrinsic. You can use ‘`llvm.ptr.annotation`’ on a pointer to an integer of any width. *NOTE* you must specify an address space for the pointer. The identifier for the default address space is the integer ‘`0`’.

    declare ptr @llvm.ptr.annotation.p0(ptr <val>, ptr <str>, ptr <str>, i32 <int>)
    declare ptr @llvm.ptr.annotation.p1(ptr addrspace(1) <val>, ptr <str>, ptr <str>, i32 <int>)

<a id="id1829"></a>

##### Overview:

The ‘`llvm.ptr.annotation`’ intrinsic.

<a id="id1830"></a>

##### Arguments:

The first argument is a pointer to an integer value of arbitrary bitwidth (result of some expression), the second is a pointer to a global string, the third is a pointer to a global string which is the source file name, and the last argument is the line number. It returns the value of the first argument.

<a id="id1831"></a>

##### Semantics:

This intrinsic allows annotation of a pointer to an integer with arbitrary strings. This can be useful for special purpose optimizations that want to look for these annotations. These have no other defined use; transformations preserve annotations on a best-effort basis but are allowed to replace the intrinsic with its first argument without breaking semantics and the intrinsic is completely dropped during instruction selection.

<a id="llvm-annotation-intrinsic"></a>

#### ‘`llvm.annotation.*`’ Intrinsic

<a id="id1832"></a>

##### Syntax:

This is an overloaded intrinsic. You can use ‘`llvm.annotation`’ on any integer bit width.

    declare i8 @llvm.annotation.i8(i8 <val>, ptr <str>, ptr <str>, i32  <int>)
    declare i16 @llvm.annotation.i16(i16 <val>, ptr <str>, ptr <str>, i32  <int>)
    declare i32 @llvm.annotation.i32(i32 <val>, ptr <str>, ptr <str>, i32  <int>)
    declare i64 @llvm.annotation.i64(i64 <val>, ptr <str>, ptr <str>, i32  <int>)
    declare i256 @llvm.annotation.i256(i256 <val>, ptr <str>, ptr <str>, i32  <int>)

<a id="id1833"></a>

##### Overview:

The ‘`llvm.annotation`’ intrinsic.

<a id="id1834"></a>

##### Arguments:

The first argument is an integer value (result of some expression), the second is a pointer to a global string, the third is a pointer to a global string which is the source file name, and the last argument is the line number. It returns the value of the first argument.

<a id="id1835"></a>

##### Semantics:

This intrinsic allows annotations to be put on arbitrary expressions with arbitrary strings. This can be useful for special purpose optimizations that want to look for these annotations. These have no other defined use; transformations preserve annotations on a best-effort basis but are allowed to replace the intrinsic with its first argument without breaking semantics and the intrinsic is completely dropped during instruction selection.

<a id="llvm-codeview-annotation-intrinsic"></a>

#### ‘`llvm.codeview.annotation`’ Intrinsic

<a id="id1836"></a>

##### Syntax:

This annotation emits a label at its program point and an associated `S_ANNOTATION` codeview record with some additional string metadata. This is used to implement MSVC’s `__annotation` intrinsic. It is marked `noduplicate`, so calls to this intrinsic prevent inlining and should be considered expensive.

    declare void @llvm.codeview.annotation(metadata)

<a id="id1837"></a>

##### Arguments:

The argument should be an MDTuple containing any number of MDStrings.

<a id="llvm-trap-intrinsic"></a>

<a id="llvm-trap"></a>

#### ‘`llvm.trap`’ Intrinsic

<a id="id1838"></a>

##### Syntax:

    declare void @llvm.trap() cold noreturn nounwind

<a id="id1839"></a>

##### Overview:

The ‘`llvm.trap`’ intrinsic.

<a id="id1840"></a>

##### Arguments:

None.

<a id="id1841"></a>

##### Semantics:

This intrinsic is lowered to the target-dependent trap instruction. If the target does not have a trap instruction, this intrinsic will be lowered to a call of the `abort()` function.

<a id="llvm-debugtrap-intrinsic"></a>

<a id="llvm-debugtrap"></a>

#### ‘`llvm.debugtrap`’ Intrinsic

<a id="id1842"></a>

##### Syntax:

    declare void @llvm.debugtrap() nounwind

<a id="id1843"></a>

##### Overview:

The ‘`llvm.debugtrap`’ intrinsic.

<a id="id1844"></a>

##### Arguments:

None.

<a id="id1845"></a>

##### Semantics:

This intrinsic is lowered to code which is intended to cause an execution trap with the intention of requesting the attention of a debugger.

<a id="llvm-ubsantrap-intrinsic"></a>

<a id="llvm-ubsantrap"></a>

#### ‘`llvm.ubsantrap`’ Intrinsic

<a id="id1846"></a>

##### Syntax:

    declare void @llvm.ubsantrap(i8 immarg) cold noreturn nounwind

<a id="id1847"></a>

##### Overview:

The ‘`llvm.ubsantrap`’ intrinsic.

<a id="id1848"></a>

##### Arguments:

An integer describing the kind of failure detected.

<a id="id1849"></a>

##### Semantics:

This intrinsic is lowered to code which is intended to cause an execution trap, embedding the argument into encoding of that trap somehow to discriminate crashes if possible.

Equivalent to `@llvm.trap` for targets that do not support this behavior.

<a id="llvm-stackprotector-intrinsic"></a>

#### ‘`llvm.stackprotector`’ Intrinsic

<a id="id1850"></a>

##### Syntax:

    declare void @llvm.stackprotector(ptr <guard>, ptr <slot>)

<a id="id1851"></a>

##### Overview:

The `llvm.stackprotector` intrinsic takes the `guard` and stores it onto the stack at `slot`. The stack slot is adjusted to ensure that it is placed on the stack before local variables.

<a id="id1852"></a>

##### Arguments:

The `llvm.stackprotector` intrinsic requires two pointer arguments. The first argument is the value loaded from the stack guard `@__stack_chk_guard`. The second variable is an `alloca` that has enough space to hold the value of the guard.

<a id="id1853"></a>

##### Semantics:

This intrinsic causes the prologue/epilogue inserter to force the position of the `AllocaInst` stack slot to be before local variables on the stack. This is to ensure that if a local variable on the stack is overwritten, it will destroy the value of the guard. When the function exits, the guard on the stack is checked against the original guard by `llvm.stackprotectorcheck`. If they are different, then `llvm.stackprotectorcheck` causes the program to abort by calling the `__stack_chk_fail()` function.

<a id="llvm-stackguard-intrinsic"></a>

#### ‘`llvm.stackguard`’ Intrinsic

<a id="id1854"></a>

##### Syntax:

    declare ptr @llvm.stackguard()

<a id="id1855"></a>

##### Overview:

The `llvm.stackguard` intrinsic returns the system stack guard value.

It should not be generated by frontends, since it is only for internal usage. The reason why we create this intrinsic is that we still support IR form Stack Protector in FastISel.

<a id="id1856"></a>

##### Arguments:

None.

<a id="id1857"></a>

##### Semantics:

On some platforms, the value returned by this intrinsic remains unchanged between loads in the same thread. On other platforms, it returns the same global variable value, if any, e.g., `@__stack_chk_guard`.

Currently some platforms have IR-level customized stack guard loading (e.g. X86 Linux) that is not handled by `llvm.stackguard()`, while they should be in the future.

<a id="llvm-objectsize-intrinsic"></a>

#### ‘`llvm.objectsize`’ Intrinsic

<a id="id1858"></a>

##### Syntax:

    declare i32 @llvm.objectsize.i32(ptr <object>, i1 <min>, i1 <nullunknown>, i1 <dynamic>)
    declare i64 @llvm.objectsize.i64(ptr <object>, i1 <min>, i1 <nullunknown>, i1 <dynamic>)

<a id="id1859"></a>

##### Overview:

The `llvm.objectsize` intrinsic is designed to provide information to the optimizer to determine whether a) an operation (like memcpy) will overflow a buffer that corresponds to an object, or b) that a runtime check for overflow isn’t necessary. An object in this context means an allocation of a specific class, structure, array, or other object.

<a id="id1860"></a>

##### Arguments:

The `llvm.objectsize` intrinsic takes four arguments. The first argument is a pointer to or into the `object`.

The second argument determines whether `llvm.objectsize` returns the minimum (if true) or maximum (if false) object size. The minimum size may be any size smaller than or equal to the actual object size (including 0 if unknown). The maximum size may be any size greater than or equal to the actual object size (including -1 if unknown).

The third argument controls how `llvm.objectsize` acts when `null` in address space 0 is used as its pointer argument. If it’s `false`, `llvm.objectsize` reports 0 bytes available when given `null`. Otherwise, if the `null` is in a non-zero address space or if `true` is given for the third argument of `llvm.objectsize`, we assume its size is unknown. The fourth argument to `llvm.objectsize` determines if the value should be evaluated at runtime.

The second, third, and fourth arguments only accept constants.

<a id="id1861"></a>

##### Semantics:

The `llvm.objectsize` intrinsic is lowered to a value representing the size of the object concerned. If the size cannot be determined, `llvm.objectsize` returns `i32/i64 -1 or 0` (depending on the `min` argument).

<a id="llvm-expect-intrinsic"></a>

#### ‘`llvm.expect`’ Intrinsic

<a id="id1862"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.expect` on any integer bit width.

    declare i1 @llvm.expect.i1(i1 <val>, i1 <expected_val>)
    declare i32 @llvm.expect.i32(i32 <val>, i32 <expected_val>)
    declare i64 @llvm.expect.i64(i64 <val>, i64 <expected_val>)

<a id="id1863"></a>

##### Overview:

The `llvm.expect` intrinsic provides information about expected (the most probable) value of `val`, which can be used by optimizers.

<a id="id1864"></a>

##### Arguments:

The `llvm.expect` intrinsic takes two arguments. The first argument is a value. The second argument is an expected value.

<a id="id1865"></a>

##### Semantics:

This intrinsic is lowered to the `val`.

<a id="llvm-expect-with-probability-intrinsic"></a>

#### ‘`llvm.expect.with.probability`’ Intrinsic

<a id="id1866"></a>

##### Syntax:

This intrinsic is similar to `llvm.expect`. This is an overloaded intrinsic. You can use `llvm.expect.with.probability` on any integer bit width.

    declare i1 @llvm.expect.with.probability.i1(i1 <val>, i1 <expected_val>, double <prob>)
    declare i32 @llvm.expect.with.probability.i32(i32 <val>, i32 <expected_val>, double <prob>)
    declare i64 @llvm.expect.with.probability.i64(i64 <val>, i64 <expected_val>, double <prob>)

<a id="id1867"></a>

##### Overview:

The `llvm.expect.with.probability` intrinsic provides information about expected value of `val` with probability(or confidence) `prob`, which can be used by optimizers.

<a id="id1868"></a>

##### Arguments:

The `llvm.expect.with.probability` intrinsic takes three arguments. The first argument is a value. The second argument is an expected value. The third argument is a probability.

<a id="id1869"></a>

##### Semantics:

This intrinsic is lowered to the `val`.

<a id="llvm-assume-intrinsic"></a>

<a id="int-assume"></a>

#### ‘`llvm.assume`’ Intrinsic

<a id="id1870"></a>

##### Syntax:

    declare void @llvm.assume(i1 %cond)

<a id="id1871"></a>

##### Overview:

The `llvm.assume` allows the optimizer to assume that the provided condition is true. This information can then be used in simplifying other parts of the code.

More complex assumptions can be encoded as [assume operand bundles](high-level-structure.md#assume-opbundles).

<a id="id1872"></a>

##### Arguments:

The argument of the call is the condition which the optimizer may assume is always true.

<a id="id1873"></a>

##### Semantics:

The intrinsic allows the optimizer to assume that the provided condition is always true whenever the control flow reaches the intrinsic call. No code is generated for this intrinsic, and instructions that contribute only to the provided condition are not used for code generation. If the condition is violated during execution, the behavior is undefined.

Note that the optimizer might limit the transformations performed on values used by the `llvm.assume` intrinsic in order to preserve the instructions only used to form the intrinsic’s input argument. This might prove undesirable if the extra information provided by the `llvm.assume` intrinsic does not cause sufficient overall improvement in code quality. For this reason, `llvm.assume` should not be used to document basic mathematical invariants that the optimizer can otherwise deduce or facts that are of little use to the optimizer.

<a id="llvm-ssa-copy-intrinsic"></a>

<a id="int-ssa-copy"></a>

#### ‘`llvm.ssa.copy`’ Intrinsic

<a id="id1874"></a>

##### Syntax:

    declare type @llvm.ssa.copy(type returned %operand) memory(none)

<a id="id1875"></a>

##### Arguments:

The first argument is an operand which is used as the returned value.

<a id="id1876"></a>

##### Overview:

The `llvm.ssa.copy` intrinsic can be used to attach information to operations by copying them and giving them new names. For example, the PredicateInfo utility uses it to build Extended SSA form, and attach various forms of information to operands that dominate specific uses. It is not meant for general use, only for building temporary renaming forms that require value splits at certain points.

<a id="llvm-type-test-intrinsic"></a>

<a id="type-test"></a>

#### ‘`llvm.type.test`’ Intrinsic

<a id="id1877"></a>

##### Syntax:

    declare i1 @llvm.type.test(ptr %ptr, metadata %type) nounwind memory(none)

<a id="id1878"></a>

##### Arguments:

The first argument is a pointer to be tested. The second argument is a metadata object representing a [type identifier](TypeMetadata.html).

<a id="id1879"></a>

##### Overview:

The `llvm.type.test` intrinsic tests whether the given pointer is associated with the given type identifier.

<a id="llvm-type-checked-load-intrinsic"></a>

<a id="type-checked-load"></a>

#### ‘`llvm.type.checked.load`’ Intrinsic

<a id="id1880"></a>

##### Syntax:

    declare {ptr, i1} @llvm.type.checked.load(ptr %ptr, i32 %offset, metadata %type) nounwind memory(argmem: read)

<a id="id1881"></a>

##### Arguments:

The first argument is a pointer from which to load a function pointer. The second argument is the byte offset from which to load the function pointer. The third argument is a metadata object representing a [type identifier](TypeMetadata.html).

<a id="id1882"></a>

##### Overview:

The `llvm.type.checked.load` intrinsic safely loads a function pointer from a virtual table pointer using type metadata. This intrinsic is used to implement control flow integrity in conjunction with virtual call optimization. The virtual call optimization pass will optimize away `llvm.type.checked.load` intrinsics associated with devirtualized calls, thereby removing the type check in cases where it is not needed to enforce the control flow integrity constraint.

If the given pointer is associated with a type metadata identifier, this function returns true as the second element of its return value. (Note that the function may also return true if the given pointer is not associated with a type metadata identifier.) If the function’s return value’s second element is true, the following rules apply to the first element:

- If the given pointer is associated with the given type metadata identifier, it is the function pointer loaded from the given byte offset from the given pointer.

- If the given pointer is not associated with the given type metadata identifier, it is one of the following (the choice of which is unspecified):

  1.  The function pointer that would have been loaded from an arbitrarily chosen (through an unspecified mechanism) pointer associated with the type metadata.

  2.  If the function has a non-void return type, a pointer to a function that returns an unspecified value without causing side effects.

If the function’s return value’s second element is false, the value of the first element is undefined.

<a id="llvm-type-checked-load-relative-intrinsic"></a>

<a id="type-checked-load-relative"></a>

#### ‘`llvm.type.checked.load.relative`’ Intrinsic

<a id="id1883"></a>

##### Syntax:

    declare {ptr, i1} @llvm.type.checked.load.relative(ptr %ptr, i32 %offset, metadata %type) nounwind memory(argmem: read)

<a id="id1884"></a>

##### Overview:

The `llvm.type.checked.load.relative` intrinsic loads a relative pointer to a function from a virtual table pointer using metadata. Otherwise, its semantic is identical to the `llvm.type.checked.load` intrinsic.

A relative pointer is a pointer to an offset. This is the offset between the destination pointer and the original pointer. The address of the destination pointer is obtained by loading this offset and adding it to the original pointer. This calculation is the same as that of the `llvm.load.relative` intrinsic.

<a id="llvm-arithmetic-fence-intrinsic"></a>

#### ‘`llvm.arithmetic.fence`’ Intrinsic

<a id="id1885"></a>

##### Syntax:

    declare <type>
    @llvm.arithmetic.fence(<type> <op>)

<a id="id1886"></a>

##### Overview:

The purpose of the `llvm.arithmetic.fence` intrinsic is to prevent the optimizer from performing fast-math optimizations, particularly reassociation, between the argument and the expression that contains the argument. It can be used to preserve the parentheses in the source language.

<a id="id1887"></a>

##### Arguments:

The `llvm.arithmetic.fence` intrinsic takes only one argument. The argument and the return value are floating-point numbers, or vector floating-point numbers, of the same type.

<a id="id1888"></a>

##### Semantics:

This intrinsic returns the value of its operand. The optimizer can optimize the argument, but the optimizer cannot hoist any component of the operand to the containing context, and the optimizer cannot move the calculation of any expression in the containing context into the operand.

<a id="llvm-donothing-intrinsic"></a>

#### ‘`llvm.donothing`’ Intrinsic

<a id="id1889"></a>

##### Syntax:

    declare void @llvm.donothing() nounwind memory(none)

<a id="id1890"></a>

##### Overview:

The `llvm.donothing` intrinsic doesn’t perform any operation. It’s one of only three intrinsics (besides `llvm.experimental.patchpoint` and `llvm.experimental.gc.statepoint`) that can be called with an invoke instruction.

<a id="id1891"></a>

##### Arguments:

None.

<a id="id1892"></a>

##### Semantics:

This intrinsic does nothing, and it’s removed by optimizers and ignored by codegen.

<a id="llvm-experimental-deoptimize-intrinsic"></a>

#### ‘`llvm.experimental.deoptimize`’ Intrinsic

<a id="id1893"></a>

##### Syntax:

    declare type @llvm.experimental.deoptimize(...) [ "deopt"(...) ]

<a id="id1894"></a>

##### Overview:

This intrinsic, together with [deoptimization operand bundles](high-level-structure.md#deopt-opbundles), allow frontends to express transfer of control and frame-local state from the currently executing (typically more specialized, hence faster) version of a function into another (typically more generic, hence slower) version.

In languages with a fully integrated managed runtime like Java and JavaScript this intrinsic can be used to implement “uncommon trap” or “side exit” like functionality. In unmanaged languages like C and C++, this intrinsic can be used to represent the slow paths of specialized functions.

<a id="id1895"></a>

##### Arguments:

The intrinsic takes an arbitrary number of arguments, whose meaning is decided by the [lowering strategy](#deoptimize-lowering).

<a id="id1896"></a>

##### Semantics:

The `@llvm.experimental.deoptimize` intrinsic executes an attached deoptimization continuation (denoted using a [deoptimization operand bundle](high-level-structure.md#deopt-opbundles)) and returns the value returned by the deoptimization continuation. Defining the semantic properties of the continuation itself is out of scope of the language reference – as far as LLVM is concerned, the deoptimization continuation can invoke arbitrary side effects, including reading from and writing to the entire heap.

Deoptimization continuations expressed using `"deopt"` operand bundles always continue execution to the end of the physical frame containing them, so all calls to `@llvm.experimental.deoptimize` must be in “tail position”:

- `@llvm.experimental.deoptimize` cannot be invoked.

- The call must immediately precede a [ret](instructions-terminators.md#i-ret) instruction.

- The `ret` instruction must return the value produced by the `@llvm.experimental.deoptimize` call if there is one, or void.

Note that the above restrictions imply that the return type for a call to `@llvm.experimental.deoptimize` will match the return type of its immediate caller.

The inliner composes the `"deopt"` continuations of the caller into the `"deopt"` continuations present in the inlinee, and also updates calls to this intrinsic to return directly from the frame of the function it inlined into.

All declarations of `@llvm.experimental.deoptimize` must share the same calling convention.

<a id="lowering"></a>

<a id="deoptimize-lowering"></a>

##### Lowering:

Calls to `@llvm.experimental.deoptimize` are lowered to calls to the symbol `__llvm_deoptimize` (it is the frontend’s responsibility to ensure that this symbol is defined). The call arguments to `@llvm.experimental.deoptimize` are lowered as if they were formal arguments of the specified types, and not as varargs.

<a id="llvm-experimental-guard-intrinsic"></a>

#### ‘`llvm.experimental.guard`’ Intrinsic

<a id="id1897"></a>

##### Syntax:

    declare void @llvm.experimental.guard(i1, ...) [ "deopt"(...) ]

<a id="id1898"></a>

##### Overview:

This intrinsic, together with [deoptimization operand bundles](high-level-structure.md#deopt-opbundles), allows frontends to express guards or checks on optimistic assumptions made during compilation. The semantics of `@llvm.experimental.guard` is defined in terms of `@llvm.experimental.deoptimize` – its body is defined to be equivalent to:

    define void @llvm.experimental.guard(i1 %pred, <args...>) {
      %realPred = and i1 %pred, undef
      br i1 %realPred, label %continue, label %leave [, !make.implicit !{}]

    leave:
      call void @llvm.experimental.deoptimize(<args...>) [ "deopt"() ]
      ret void

    continue:
      ret void
    }

with the optional `[, !make.implicit !{}]` present if and only if it is present on the call site. For more details on `!make.implicit`, see [FaultMaps and implicit checks](FaultMaps.html).

In words, `@llvm.experimental.guard` executes the attached `"deopt"` continuation if (but **not** only if) its first argument is `false`. Since the optimizer is allowed to replace the `undef` with an arbitrary value, it can optimize guard to fail “spuriously”, i.e., without the original condition being false (hence the “not only if”); and this allows for “check widening” type optimizations.

`@llvm.experimental.guard` cannot be invoked.

After `@llvm.experimental.guard` was first added, a more general formulation was found in `@llvm.experimental.widenable.condition`. Support for `@llvm.experimental.guard` is slowly being rephrased in terms of this alternate.

<a id="llvm-experimental-widenable-condition-intrinsic"></a>

#### ‘`llvm.experimental.widenable.condition`’ Intrinsic

<a id="id1899"></a>

##### Syntax:

    declare i1 @llvm.experimental.widenable.condition()

<a id="id1900"></a>

##### Overview:

This intrinsic represents a “widenable condition” which is boolean expressions with the following property: whether this expression is `true` or `false`, the program is correct and well-defined.

Together with [deoptimization operand bundles](high-level-structure.md#deopt-opbundles), `@llvm.experimental.widenable.condition` allows frontends to express guards or checks on optimistic assumptions made during compilation and represent them as branch instructions on special conditions.

While this may appear similar in semantics to `undef`, it is very different in that an invocation produces a particular, singular value. It is also intended to be lowered late, and remain available for specific optimizations and transforms that can benefit from its special properties.

<a id="id1901"></a>

##### Arguments:

None.

<a id="id1902"></a>

##### Semantics:

The intrinsic `@llvm.experimental.widenable.condition()` returns either `true` or `false`. For each evaluation of a call to this intrinsic, the program must be valid and correct both if it returns `true` and if it returns `false`. This allows transformation passes to replace evaluations of this intrinsic with either value whenever one is beneficial.

When used in a branch condition, it allows us to choose between two alternative correct solutions for the same problem, like in example below:

      %cond = call i1 @llvm.experimental.widenable.condition()
      br i1 %cond, label %fast_path, label %slow_path

    fast_path:
      ; Apply memory-consuming but fast solution for a task.

    slow_path:
      ; Cheap in memory but slow solution.

Whether the result of intrinsic’s call is `true` or `false`, it should be correct to pick either solution. We can switch between them by replacing the result of `@llvm.experimental.widenable.condition` with different `i1` expressions.

This is how it can be used to represent guards as widenable branches:

    block:
      ; Unguarded instructions
      call void @llvm.experimental.guard(i1 %cond, <args...>) ["deopt"(<deopt_args...>)]
      ; Guarded instructions

Can be expressed in an alternative equivalent form of explicit branch using `@llvm.experimental.widenable.condition`:

    block:
      ; Unguarded instructions
      %widenable_condition = call i1 @llvm.experimental.widenable.condition()
      %guard_condition = and i1 %cond, %widenable_condition
      br i1 %guard_condition, label %guarded, label %deopt

    guarded:
      ; Guarded instructions

    deopt:
      call type @llvm.experimental.deoptimize(<args...>) [ "deopt"(<deopt_args...>) ]

So the block `guarded` is only reachable when `%cond` is `true`, and it should be valid to go to the block `deopt` whenever `%cond` is `true` or `false`.

`@llvm.experimental.widenable.condition` will never throw, thus it cannot be invoked.

<a id="guard-widening"></a>

##### Guard widening:

When `@llvm.experimental.widenable.condition()` is used in condition of a guard represented as explicit branch, it is legal to widen the guard’s condition with any additional conditions.

Guard widening looks like replacement of

    %widenable_cond = call i1 @llvm.experimental.widenable.condition()
    %guard_cond = and i1 %cond, %widenable_cond
    br i1 %guard_cond, label %guarded, label %deopt

with

    %widenable_cond = call i1 @llvm.experimental.widenable.condition()
    %new_cond = and i1 %any_other_cond, %widenable_cond
    %new_guard_cond = and i1 %cond, %new_cond
    br i1 %new_guard_cond, label %guarded, label %deopt

for this branch. Here `%any_other_cond` is an arbitrarily chosen well-defined `i1` value. By making guard widening, we may impose stricter conditions on `guarded` block and bail to the deopt when the new condition is not met.

<a id="id1903"></a>

##### Lowering:

Default lowering strategy is replacing the result of call of `@llvm.experimental.widenable.condition` with constant `true`. However it is always correct to replace it with any other `i1` value. Any pass can freely do it if it can benefit from non-default lowering.

<a id="llvm-allow-ubsan-check-intrinsic"></a>

#### ‘`llvm.allow.ubsan.check`’ Intrinsic

<a id="id1904"></a>

##### Syntax:

    declare i1 @llvm.allow.ubsan.check(i8 immarg %kind)

<a id="id1905"></a>

##### Overview:

This intrinsic returns `true` if and only if the compiler opted to enable the ubsan check in the current basic block.

Rules to allow ubsan checks are not part of the intrinsic declaration, and controlled by compiler options.

This intrinsic is the ubsan specific version of `@llvm.allow.runtime.check()`.

<a id="id1906"></a>

##### Arguments:

An integer describing the kind of ubsan check guarded by the intrinsic.

<a id="id1907"></a>

##### Semantics:

The intrinsic `@llvm.allow.ubsan.check()` returns either `true` or `false`, depending on compiler options.

For each evaluation of a call to this intrinsic, the program must be valid and correct both if it returns `true` and if it returns `false`.

When used in a branch condition, it selects one of the two paths:

- `true`: Executes the UBSan check and reports any failures.

- `false`: Bypasses the check, assuming it always succeeds.

Example:

      %allow = call i1 @llvm.allow.ubsan.check(i8 5)
      %not.allow = xor i1 %allow, true
      %cond = or i1 %ubcheck, %not.allow
      br i1 %cond, label %cont, label %trap

    cont:
      ; Proceed

    trap:
      call void @llvm.ubsantrap(i8 5)
      unreachable

<a id="llvm-allow-runtime-check-intrinsic"></a>

#### ‘`llvm.allow.runtime.check`’ Intrinsic

<a id="id1908"></a>

##### Syntax:

    declare i1 @llvm.allow.runtime.check(metadata %kind)

<a id="id1909"></a>

##### Overview:

This intrinsic returns `true` if and only if the compiler opted to enable runtime checks in the current basic block.

Rules to allow runtime checks are not part of the intrinsic declaration, and controlled by compiler options.

This intrinsic is non-ubsan specific version of `@llvm.allow.ubsan.check()`.

<a id="id1910"></a>

##### Arguments:

A string identifying the kind of runtime check guarded by the intrinsic. The string can be used to control rules to allow checks.

<a id="id1911"></a>

##### Semantics:

The intrinsic `@llvm.allow.runtime.check()` returns either `true` or `false`, depending on compiler options.

For each evaluation of a call to this intrinsic, the program must be valid and correct both if it returns `true` and if it returns `false`.

When used in a branch condition, it allows us to choose between two alternative correct solutions for the same problem.

If the intrinsic is evaluated as `true`, program should execute a guarded check. If the intrinsic is evaluated as `false`, the program should avoid any unnecessary checks.

Example:

      %allow = call i1 @llvm.allow.runtime.check(metadata !"my_check")
      br i1 %allow, label %fast_path, label %slow_path

    fast_path:
      ; Omit diagnostics.

    slow_path:
      ; Additional diagnostics.

<a id="llvm-load-relative-intrinsic"></a>

#### ‘`llvm.load.relative`’ Intrinsic

<a id="id1912"></a>

##### Syntax:

    declare ptr @llvm.load.relative.iN(ptr %ptr, iN %offset) nounwind memory(argmem: read)

<a id="id1913"></a>

##### Overview:

This intrinsic loads a 32-bit value from the address `%ptr + %offset`, adds `%ptr` to that value and returns it. The constant folder specifically recognizes the form of this intrinsic and the constant initializers it may load from; if a loaded constant initializer is known to have the form `i32 trunc(x - %ptr)`, the intrinsic call is folded to `x`.

LLVM provides that the calculation of such a constant initializer will not overflow at link time under the medium code model if `x` is an `unnamed_addr` function. However, it does not provide this guarantee for a constant initializer folded into a function body. This intrinsic can be used to avoid the possibility of overflows when loading from such a constant.

<a id="llvm-sideeffect-intrinsic"></a>

<a id="llvm-sideeffect"></a>

#### ‘`llvm.sideeffect`’ Intrinsic

<a id="id1914"></a>

##### Syntax:

    declare void @llvm.sideeffect() inaccessiblememonly nounwind willreturn

<a id="id1915"></a>

##### Overview:

The `llvm.sideeffect` intrinsic doesn’t perform any operation. Optimizers treat it as having side effects, so it can be inserted into a loop to indicate that the loop shouldn’t be assumed to terminate (which could potentially lead to the loop being optimized away entirely), even if it’s an infinite loop with no other side effects.

<a id="id1916"></a>

##### Arguments:

None.

<a id="id1917"></a>

##### Semantics:

This intrinsic actually does nothing, but optimizers must assume that it has externally observable side effects.

<a id="llvm-is-constant-intrinsic"></a>

#### ‘`llvm.is.constant.*`’ Intrinsic

<a id="id1918"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.is.constant` with any argument type.

    declare i1 @llvm.is.constant.i32(i32 %operand) nounwind memory(none)
    declare i1 @llvm.is.constant.f32(float %operand) nounwind memory(none)
    declare i1 @llvm.is.constant.TYPENAME(TYPE %operand) nounwind memory(none)

<a id="id1919"></a>

##### Overview:

The ‘`llvm.is.constant`’ intrinsic will return true if the argument is known to be a manifest compile-time constant. It is guaranteed to fold to either true or false before generating machine code.

<a id="id1920"></a>

##### Semantics:

This intrinsic generates no code. If its argument is known to be a manifest compile-time constant value, then the intrinsic will be converted to a constant true value. Otherwise, it will be converted to a constant false value.

In particular, note that if the argument is a constant expression which refers to a global (the address of which *is* a constant, but not manifest during the compile), then the intrinsic evaluates to false.

The result also intentionally depends on the result of optimization passes – e.g., the result can change depending on whether a function gets inlined or not. A function’s parameters are obviously not constant. However, a call like `llvm.is.constant.i32(i32 %param)` *can* return true after the function is inlined, if the value passed to the function parameter was a constant.

<a id="llvm-ptrmask-intrinsic"></a>

<a id="int-ptrmask"></a>

#### ‘`llvm.ptrmask`’ Intrinsic

<a id="id1921"></a>

##### Syntax:

    declare ptrty llvm.ptrmask(ptrty %ptr, intty %mask) speculatable memory(none)

<a id="id1922"></a>

##### Arguments:

The first argument is a pointer or vector of pointers. The second argument is an integer or vector of integers with the same bit width as the index type size of the first argument.

<a id="id1923"></a>

##### Overview:

The `llvm.ptrmask` intrinsic masks out bits of the pointer according to a mask. This allows stripping data from tagged pointers without converting them to an integer (ptrtoint/inttoptr). As a consequence, we can preserve more information to facilitate alias analysis and underlying-object detection.

<a id="id1924"></a>

##### Semantics:

The result of `ptrmask(%ptr, %mask)` is equivalent to the following expansion, where `iPtrIdx` is the index type size of the pointer:

    %intptr = ptrtoint ptr %ptr to iPtrIdx ; this may truncate
    %masked = and iPtrIdx %intptr, %mask
    %diff = sub iPtrIdx %masked, %intptr
    %result = getelementptr i8, ptr %ptr, iPtrIdx %diff

If the pointer index type size is smaller than the pointer type size, this implies that pointer bits beyond the index size are not affected by this intrinsic. For integral pointers, it behaves as if the mask were extended with 1 bits to the pointer type size.

Both the returned pointer(s) and the first argument are based on the same underlying object (for more information on the *based on* terminology see [the pointer aliasing rules](high-level-structure.md#pointeraliasing)).

The intrinsic only captures the pointer argument through the return value.

<a id="llvm-threadlocal-address-intrinsic"></a>

<a id="int-threadlocal-address"></a>

#### ‘`llvm.threadlocal.address`’ Intrinsic

<a id="id1925"></a>

##### Syntax:

    declare ptr @llvm.threadlocal.address(ptr) nounwind willreturn memory(none)

<a id="id1926"></a>

##### Arguments:

The `llvm.threadlocal.address` intrinsic requires a global value argument (a [global variable](high-level-structure.md#globalvars) or alias) that is thread local.

<a id="id1927"></a>

##### Semantics:

The address of a thread local global is not a constant, since it depends on the calling thread. The `llvm.threadlocal.address` intrinsic returns the address of the given thread local global in the calling thread.

<a id="llvm-vscale-intrinsic"></a>

<a id="int-vscale"></a>

#### ‘`llvm.vscale`’ Intrinsic

<a id="id1928"></a>

##### Syntax:

    declare i32 llvm.vscale.i32()
    declare i64 llvm.vscale.i64()

<a id="id1929"></a>

##### Overview:

The `llvm.vscale` intrinsic returns the value for `vscale` in scalable vectors such as `<vscale x 16 x i8>`.

<a id="id1930"></a>

##### Semantics:

`vscale` is a positive power-of-two integer that is constant throughout program execution, but is unknown at compile time. If the result value does not fit in the result type, then the result is a [poison value](constants.md#poisonvalues).

<a id="llvm-fake-use-intrinsic"></a>

<a id="llvm-fake-use"></a>

#### ‘`llvm.fake.use`’ Intrinsic

<a id="id1931"></a>

##### Syntax:

    declare void @llvm.fake.use(...)

<a id="id1932"></a>

##### Overview:

The `llvm.fake.use` intrinsic is a no-op. It takes a single value as an operand and is treated as a use of that operand, to force the optimizer to preserve that value prior to the fake use. This is used for extending the lifetimes of variables, where this intrinsic placed at the end of a variable’s scope helps prevent that variable from being optimized out.

<a id="id1933"></a>

##### Arguments:

The `llvm.fake.use` intrinsic takes one argument, which may be any function-local SSA value. Note that the signature is variadic so that the intrinsic can take any type of argument, but passing more than one argument will result in an error.

<a id="id1934"></a>

##### Semantics:

This intrinsic does nothing, but optimizers must consider it a use of its single operand and should try to preserve the intrinsic and its position in the function.

<a id="llvm-reloc-none-intrinsic"></a>

<a id="llvm-reloc-none"></a>

#### ‘`llvm.reloc.none`’ Intrinsic

<a id="id1935"></a>

##### Syntax:

    declare void @llvm.reloc.none(metadata !<name_str>)

<a id="id1936"></a>

##### Overview:

The `llvm.reloc.none` intrinsic emits a no-op relocation against a given operand symbol. This can bring the symbol definition into the link without emitting any code or data to the binary for that purpose.

<a id="id1937"></a>

##### Arguments:

The `llvm.reloc.none` intrinsic takes the symbol as a metadata string argument.

<a id="id1938"></a>

##### Semantics:

This intrinsic emits a no-op relocation for the symbol at the location of the intrinsic call.

<a id="stack-map-intrinsics"></a>

### Stack Map Intrinsics

LLVM provides experimental intrinsics to support runtime patching mechanisms commonly desired in dynamic language JITs. These intrinsics are described in [Stack maps and patch points in LLVM](StackMaps.html).

<a id="element-wise-atomic-memory-intrinsics"></a>

### Element Wise Atomic Memory Intrinsics

These intrinsics are similar to the standard library memory intrinsics except that they perform memory transfer as a sequence of atomic memory accesses.

<a id="llvm-memcpy-element-unordered-atomic-intrinsic"></a>

<a id="int-memcpy-element-unordered-atomic"></a>

#### ‘`llvm.memcpy.element.unordered.atomic`’ Intrinsic

<a id="id1939"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memcpy.element.unordered.atomic` on any integer bit width and for different address spaces. Not all targets support all bit widths however.

    declare void @llvm.memcpy.element.unordered.atomic.p0.p0.i32(ptr <dest>,
                                                                 ptr <src>,
                                                                 i32 <len>,
                                                                 i32 <element_size>)
    declare void @llvm.memcpy.element.unordered.atomic.p0.p0.i64(ptr <dest>,
                                                                 ptr <src>,
                                                                 i64 <len>,
                                                                 i32 <element_size>)

<a id="id1940"></a>

##### Overview:

The ‘`llvm.memcpy.element.unordered.atomic.*`’ intrinsic is a specialization of the ‘`llvm.memcpy.*`’ intrinsic. It differs in that the `dest` and `src` are treated as arrays with elements that are exactly `element_size` bytes, and the copy between buffers uses a sequence of [unordered atomic](high-level-structure.md#ordering) load/store operations that are a positive integer multiple of the `element_size` in size.

<a id="id1941"></a>

##### Arguments:

The first three arguments are the same as they are in the [@llvm.memcpy](intrinsics-libc-and-arithmetic.md#int-memcpy) intrinsic, with the added constraint that `len` is required to be a positive integer multiple of the `element_size`. If `len` is not a positive integer multiple of `element_size`, then the behavior of the intrinsic is undefined.

`element_size` must be a compile-time constant positive power of two no greater than target-specific atomic access size limit.

For each of the input pointers `align` parameter attribute must be specified. It must be a power of two no less than the `element_size`. Caller guarantees that both the source and destination pointers are aligned to that boundary.

<a id="id1942"></a>

##### Semantics:

The ‘`llvm.memcpy.element.unordered.atomic.*`’ intrinsic copies `len` bytes of memory from the source location to the destination location. These locations are not allowed to overlap. The memory copy is performed as a sequence of load/store operations where each access is guaranteed to be a multiple of `element_size` bytes wide and aligned at an `element_size` boundary.

The order of the copy is unspecified. The same value may be read from the source buffer many times, but only one write is issued to the destination buffer per element. It is well defined to have concurrent reads and writes to both source and destination provided those reads and writes are unordered atomic when specified.

This intrinsic does not provide any additional ordering guarantees over those provided by a set of unordered loads from the source location and stores to the destination.

<a id="id1943"></a>

##### Lowering:

In the most general case call to the ‘`llvm.memcpy.element.unordered.atomic.*`’ is lowered to a call to the symbol `__llvm_memcpy_element_unordered_atomic_*`. Where ‘\*’ is replaced with an actual element size. See [RewriteStatepointsForGC intrinsic lowering](Statepoints.html#rewritestatepointsforgc-intrinsic-lowering) for details on GC specific lowering.

Optimizer is allowed to inline memory copy when it’s profitable to do so.

<a id="llvm-memmove-element-unordered-atomic-intrinsic"></a>

#### ‘`llvm.memmove.element.unordered.atomic`’ Intrinsic

<a id="id1944"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memmove.element.unordered.atomic` on any integer bit width and for different address spaces. Not all targets support all bit widths however.

    declare void @llvm.memmove.element.unordered.atomic.p0.p0.i32(ptr <dest>,
                                                                  ptr <src>,
                                                                  i32 <len>,
                                                                  i32 <element_size>)
    declare void @llvm.memmove.element.unordered.atomic.p0.p0.i64(ptr <dest>,
                                                                  ptr <src>,
                                                                  i64 <len>,
                                                                  i32 <element_size>)

<a id="id1945"></a>

##### Overview:

The ‘`llvm.memmove.element.unordered.atomic.*`’ intrinsic is a specialization of the ‘`llvm.memmove.*`’ intrinsic. It differs in that the `dest` and `src` are treated as arrays with elements that are exactly `element_size` bytes, and the copy between buffers uses a sequence of [unordered atomic](high-level-structure.md#ordering) load/store operations that are a positive integer multiple of the `element_size` in size.

<a id="id1946"></a>

##### Arguments:

The first three arguments are the same as they are in the [@llvm.memmove](intrinsics-libc-and-arithmetic.md#int-memmove) intrinsic, with the added constraint that `len` is required to be a positive integer multiple of the `element_size`. If `len` is not a positive integer multiple of `element_size`, then the behavior of the intrinsic is undefined.

`element_size` must be a compile-time constant positive power of two no greater than a target-specific atomic access size limit.

For each of the input pointers the `align` parameter attribute must be specified. It must be a power of two no less than the `element_size`. Caller guarantees that both the source and destination pointers are aligned to that boundary.

<a id="id1947"></a>

##### Semantics:

The ‘`llvm.memmove.element.unordered.atomic.*`’ intrinsic copies `len` bytes of memory from the source location to the destination location. These locations are allowed to overlap. The memory copy is performed as a sequence of load/store operations where each access is guaranteed to be a multiple of `element_size` bytes wide and aligned at an `element_size` boundary.

The order of the copy is unspecified. The same value may be read from the source buffer many times, but only one write is issued to the destination buffer per element. It is well defined to have concurrent reads and writes to both source and destination provided those reads and writes are unordered atomic when specified.

This intrinsic does not provide any additional ordering guarantees over those provided by a set of unordered loads from the source location and stores to the destination.

<a id="id1948"></a>

##### Lowering:

In the most general case call to the ‘`llvm.memmove.element.unordered.atomic.*`’ is lowered to a call to the symbol `__llvm_memmove_element_unordered_atomic_*`. Where ‘\*’ is replaced with an actual element size. See [RewriteStatepointsForGC intrinsic lowering](Statepoints.html#rewritestatepointsforgc-intrinsic-lowering) for details on GC specific lowering.

The optimizer is allowed to inline the memory copy when it’s profitable to do so.

<a id="llvm-memset-element-unordered-atomic-intrinsic"></a>

<a id="int-memset-element-unordered-atomic"></a>

#### ‘`llvm.memset.element.unordered.atomic`’ Intrinsic

<a id="id1949"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.memset.element.unordered.atomic` on any integer bit width and for different address spaces. Not all targets support all bit widths however.

    declare void @llvm.memset.element.unordered.atomic.p0.i32(ptr <dest>,
                                                              i8 <value>,
                                                              i32 <len>,
                                                              i32 <element_size>)
    declare void @llvm.memset.element.unordered.atomic.p0.i64(ptr <dest>,
                                                              i8 <value>,
                                                              i64 <len>,
                                                              i32 <element_size>)

<a id="id1950"></a>

##### Overview:

The ‘`llvm.memset.element.unordered.atomic.*`’ intrinsic is a specialization of the ‘`llvm.memset.*`’ intrinsic. It differs in that the `dest` is treated as an array with elements that are exactly `element_size` bytes, and the assignment to that array uses uses a sequence of [unordered atomic](high-level-structure.md#ordering) store operations that are a positive integer multiple of the `element_size` in size.

<a id="id1951"></a>

##### Arguments:

The first three arguments are the same as they are in the [@llvm.memset](intrinsics-libc-and-arithmetic.md#int-memset) intrinsic, with the added constraint that `len` is required to be a positive integer multiple of the `element_size`. If `len` is not a positive integer multiple of `element_size`, then the behavior of the intrinsic is undefined.

`element_size` must be a compile-time constant positive power of two no greater than target-specific atomic access size limit.

The `dest` input pointer must have the `align` parameter attribute specified. It must be a power of two no less than the `element_size`. Caller guarantees that the destination pointer is aligned to that boundary.

<a id="id1952"></a>

##### Semantics:

The ‘`llvm.memset.element.unordered.atomic.*`’ intrinsic sets the `len` bytes of memory starting at the destination location to the given `value`. The memory is set with a sequence of store operations where each access is guaranteed to be a multiple of `element_size` bytes wide and aligned at an `element_size` boundary.

The order of the assignment is unspecified. Only one write is issued to the destination buffer per element. It is well defined to have concurrent reads and writes to the destination provided those reads and writes are unordered atomic when specified.

This intrinsic does not provide any additional ordering guarantees over those provided by a set of unordered stores to the destination.

<a id="id1953"></a>

##### Lowering:

In the most general case call to the ‘`llvm.memset.element.unordered.atomic.*`’ is lowered to a call to the symbol `__llvm_memset_element_unordered_atomic_*`. Where ‘\*’ is replaced with an actual element size.

The optimizer is allowed to inline the memory assignment when it’s profitable to do so.

<a id="objective-c-arc-runtime-intrinsics"></a>

### Objective-C ARC Runtime Intrinsics

LLVM provides intrinsics that lower to Objective-C ARC runtime entry points. LLVM is aware of the semantics of these functions, and optimizes based on that knowledge. You can read more about the details of Objective-C ARC [here](https://clang.llvm.org/docs/AutomaticReferenceCounting.html).

<a id="llvm-objc-autorelease-intrinsic"></a>

#### ‘`llvm.objc.autorelease`’ Intrinsic

<a id="id1954"></a>

##### Syntax:

    declare ptr @llvm.objc.autorelease(ptr)

<a id="id1955"></a>

##### Lowering:

Lowers to a call to [objc_autorelease](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-autorelease).

<a id="llvm-objc-autoreleasepoolpop-intrinsic"></a>

#### ‘`llvm.objc.autoreleasePoolPop`’ Intrinsic

<a id="id1956"></a>

##### Syntax:

    declare void @llvm.objc.autoreleasePoolPop(ptr)

<a id="id1957"></a>

##### Lowering:

Lowers to a call to [objc_autoreleasePoolPop](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#void-objc-autoreleasepoolpop-void-pool).

<a id="llvm-objc-autoreleasepoolpush-intrinsic"></a>

#### ‘`llvm.objc.autoreleasePoolPush`’ Intrinsic

<a id="id1958"></a>

##### Syntax:

    declare ptr @llvm.objc.autoreleasePoolPush()

<a id="id1959"></a>

##### Lowering:

Lowers to a call to [objc_autoreleasePoolPush](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#void-objc-autoreleasepoolpush-void).

<a id="llvm-objc-autoreleasereturnvalue-intrinsic"></a>

#### ‘`llvm.objc.autoreleaseReturnValue`’ Intrinsic

<a id="id1960"></a>

##### Syntax:

    declare ptr @llvm.objc.autoreleaseReturnValue(ptr)

<a id="id1961"></a>

##### Lowering:

Lowers to a call to [objc_autoreleaseReturnValue](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-autoreleasereturnvalue).

<a id="llvm-objc-copyweak-intrinsic"></a>

#### ‘`llvm.objc.copyWeak`’ Intrinsic

<a id="id1962"></a>

##### Syntax:

    declare void @llvm.objc.copyWeak(ptr, ptr)

<a id="id1963"></a>

##### Lowering:

Lowers to a call to [objc_copyWeak](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#void-objc-copyweak-id-dest-id-src).

<a id="llvm-objc-destroyweak-intrinsic"></a>

#### ‘`llvm.objc.destroyWeak`’ Intrinsic

<a id="id1964"></a>

##### Syntax:

    declare void @llvm.objc.destroyWeak(ptr)

<a id="id1965"></a>

##### Lowering:

Lowers to a call to [objc_destroyWeak](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#void-objc-destroyweak-id-object).

<a id="llvm-objc-initweak-intrinsic"></a>

#### ‘`llvm.objc.initWeak`’ Intrinsic

<a id="id1966"></a>

##### Syntax:

    declare ptr @llvm.objc.initWeak(ptr, ptr)

<a id="id1967"></a>

##### Lowering:

Lowers to a call to [objc_initWeak](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-initweak).

<a id="llvm-objc-loadweak-intrinsic"></a>

#### ‘`llvm.objc.loadWeak`’ Intrinsic

<a id="id1968"></a>

##### Syntax:

    declare ptr @llvm.objc.loadWeak(ptr)

<a id="id1969"></a>

##### Lowering:

Lowers to a call to [objc_loadWeak](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-loadweak).

<a id="llvm-objc-loadweakretained-intrinsic"></a>

#### ‘`llvm.objc.loadWeakRetained`’ Intrinsic

<a id="id1970"></a>

##### Syntax:

    declare ptr @llvm.objc.loadWeakRetained(ptr)

<a id="id1971"></a>

##### Lowering:

Lowers to a call to [objc_loadWeakRetained](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-loadweakretained).

<a id="llvm-objc-moveweak-intrinsic"></a>

#### ‘`llvm.objc.moveWeak`’ Intrinsic

<a id="id1972"></a>

##### Syntax:

    declare void @llvm.objc.moveWeak(ptr, ptr)

<a id="id1973"></a>

##### Lowering:

Lowers to a call to [objc_moveWeak](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#void-objc-moveweak-id-dest-id-src).

<a id="llvm-objc-release-intrinsic"></a>

#### ‘`llvm.objc.release`’ Intrinsic

<a id="id1974"></a>

##### Syntax:

    declare void @llvm.objc.release(ptr)

<a id="id1975"></a>

##### Lowering:

Lowers to a call to [objc_release](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#void-objc-release-id-value).

<a id="llvm-objc-retain-intrinsic"></a>

#### ‘`llvm.objc.retain`’ Intrinsic

<a id="id1976"></a>

##### Syntax:

    declare ptr @llvm.objc.retain(ptr)

<a id="id1977"></a>

##### Lowering:

Lowers to a call to [objc_retain](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-retain).

<a id="llvm-objc-retainautorelease-intrinsic"></a>

#### ‘`llvm.objc.retainAutorelease`’ Intrinsic

<a id="id1978"></a>

##### Syntax:

    declare ptr @llvm.objc.retainAutorelease(ptr)

<a id="id1979"></a>

##### Lowering:

Lowers to a call to [objc_retainAutorelease](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-retainautorelease).

<a id="llvm-objc-retainautoreleasereturnvalue-intrinsic"></a>

#### ‘`llvm.objc.retainAutoreleaseReturnValue`’ Intrinsic

<a id="id1980"></a>

##### Syntax:

    declare ptr @llvm.objc.retainAutoreleaseReturnValue(ptr)

<a id="id1981"></a>

##### Lowering:

Lowers to a call to [objc_retainAutoreleaseReturnValue](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-retainautoreleasereturnvalue).

<a id="llvm-objc-retainautoreleasedreturnvalue-intrinsic"></a>

#### ‘`llvm.objc.retainAutoreleasedReturnValue`’ Intrinsic

<a id="id1982"></a>

##### Syntax:

    declare ptr @llvm.objc.retainAutoreleasedReturnValue(ptr)

<a id="id1983"></a>

##### Lowering:

Lowers to a call to [objc_retainAutoreleasedReturnValue](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-retainautoreleasedreturnvalue).

<a id="llvm-objc-retainblock-intrinsic"></a>

#### ‘`llvm.objc.retainBlock`’ Intrinsic

<a id="id1984"></a>

##### Syntax:

    declare ptr @llvm.objc.retainBlock(ptr)

<a id="id1985"></a>

##### Lowering:

Lowers to a call to [objc_retainBlock](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-retainblock).

<a id="llvm-objc-storestrong-intrinsic"></a>

#### ‘`llvm.objc.storeStrong`’ Intrinsic

<a id="id1986"></a>

##### Syntax:

    declare void @llvm.objc.storeStrong(ptr, ptr)

<a id="id1987"></a>

##### Lowering:

Lowers to a call to [objc_storeStrong](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#void-objc-storestrong-id-object-id-value).

<a id="llvm-objc-storeweak-intrinsic"></a>

#### ‘`llvm.objc.storeWeak`’ Intrinsic

<a id="id1988"></a>

##### Syntax:

    declare ptr @llvm.objc.storeWeak(ptr, ptr)

<a id="id1989"></a>

##### Lowering:

Lowers to a call to [objc_storeWeak](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-storeweak).

<a id="preserving-debug-information-intrinsics"></a>

### Preserving Debug Information Intrinsics

These intrinsics are used to carry certain debuginfo together with IR-level operations. For example, it may be desirable to know the structure/union name and the original user-level field indices. Such information got lost in IR GetElementPtr instruction since the IR types are different from debugInfo types and unions are converted to structs in IR.

<a id="llvm-preserve-array-access-index-intrinsic"></a>

#### ‘`llvm.preserve.array.access.index`’ Intrinsic

<a id="id1990"></a>

##### Syntax:

    declare <ret_type>
    @llvm.preserve.array.access.index.p0s_union.anons.p0a10s_union.anons(<type> base,
                                                                         i32 dim,
                                                                         i32 index)

<a id="id1991"></a>

##### Overview:

The ‘`llvm.preserve.array.access.index`’ intrinsic returns the getelementptr address based on array base `base`, array dimension `dim` and the last access index `index` into the array. The return type `ret_type` is a pointer type to the array element. The array `dim` and `index` are preserved which is more robust than getelementptr instruction which may be subject to compiler transformation. The `llvm.preserve.access.index` type of metadata is attached to this call instruction to provide array or pointer debuginfo type. The metadata is a `DICompositeType` or `DIDerivedType` representing the debuginfo version of `type`.

<a id="id1992"></a>

##### Arguments:

The `base` is the array base address. The `dim` is the array dimension. The `base` is a pointer if `dim` equals 0. The `index` is the last access index into the array or pointer.

The `base` argument must be annotated with an [elementtype](high-level-structure.md#attr-elementtype) attribute at the call-site. This attribute specifies the getelementptr element type.

<a id="id1993"></a>

##### Semantics:

The ‘`llvm.preserve.array.access.index`’ intrinsic produces the same result as a getelementptr with base `base` and access operands `{dim's 0's, index}`.

<a id="llvm-preserve-union-access-index-intrinsic"></a>

#### ‘`llvm.preserve.union.access.index`’ Intrinsic

<a id="id1994"></a>

##### Syntax:

    declare <type>
    @llvm.preserve.union.access.index.p0s_union.anons.p0s_union.anons(<type> base,
                                                                      i32 di_index)

<a id="id1995"></a>

##### Overview:

The ‘`llvm.preserve.union.access.index`’ intrinsic carries the debuginfo field index `di_index` and returns the `base` address. The `llvm.preserve.access.index` type of metadata is attached to this call instruction to provide union debuginfo type. The metadata is a `DICompositeType` representing the debuginfo version of `type`. The return type `type` is the same as the `base` type.

<a id="id1996"></a>

##### Arguments:

The `base` is the union base address. The `di_index` is the field index in debuginfo.

<a id="id1997"></a>

##### Semantics:

The ‘`llvm.preserve.union.access.index`’ intrinsic returns the `base` address.

<a id="llvm-preserve-struct-access-index-intrinsic"></a>

#### ‘`llvm.preserve.struct.access.index`’ Intrinsic

<a id="id1998"></a>

##### Syntax:

    declare <ret_type>
    @llvm.preserve.struct.access.index.p0i8.p0s_struct.anon.0s(<type> base,
                                                               i32 gep_index,
                                                               i32 di_index)

<a id="id1999"></a>

##### Overview:

The ‘`llvm.preserve.struct.access.index`’ intrinsic returns the getelementptr address based on struct base `base` and IR struct member index `gep_index`. The `llvm.preserve.access.index` type of metadata is attached to this call instruction to provide struct debuginfo type. The metadata is a `DICompositeType` representing the debuginfo version of `type`. The return type `ret_type` is a pointer type to the structure member.

<a id="id2000"></a>

##### Arguments:

The `base` is the structure base address. The `gep_index` is the struct member index based on IR structures. The `di_index` is the struct member index based on debuginfo.

The `base` argument must be annotated with an [elementtype](high-level-structure.md#attr-elementtype) attribute at the call-site. This attribute specifies the getelementptr element type.

<a id="id2001"></a>

##### Semantics:

The ‘`llvm.preserve.struct.access.index`’ intrinsic produces the same result as a getelementptr with base `base` and access operands `{0, gep_index}`.

<a id="llvm-protected-field-ptr-intrinsic"></a>

#### ‘`llvm.protected.field.ptr`’ Intrinsic

<a id="id2002"></a>

##### Syntax:

    declare ptr @llvm.protected.field.ptr(ptr ptr, i64 disc, i1 use_hw_encoding)

<a id="id2003"></a>

##### Overview:

The ‘`llvm.protected.field.ptr`’ intrinsic returns a pointer to the storage location of a pointer that has special properties as described below.

<a id="id2004"></a>

##### Arguments:

The first argument is the pointer specifying the location to store the pointer. The second argument is the discriminator, which is used as an input for the pointer encoding. The third argument specifies whether to use a target-specific mechanism to encode the pointer.

<a id="id2005"></a>

##### Semantics:

This intrinsic returns a pointer which may be used to store a pointer at the specified address that is encoded using the specified discriminator. Stores via the pointer will cause the stored pointer to be blended with the second argument before being stored. The blend operation shall be either a weak but cheap and target-independent operation (if the third argument is 0) or a stronger target-specific operation (if the third argument is 1). When loading from the pointer, the inverse operation is done on the loaded pointer after it is loaded. Specifically, when the third argument is 1, the pointer is signed (using pointer authentication instructions or emulated PAC if not supported by the hardware) using the discriminator before being stored, and authenticated after being loaded. Note that it is currently unsupported to have the third argument be 1 on targets other than AArch64, and it is also currently unsupported to have the third argument be 0 at all.

If the pointer is used other than for loading or storing (e.g. its address escapes), that will disable all blending operations using the deactivation symbol specified in the intrinsic’s operand bundle. The deactivation symbol operand bundle is copied onto any sign and auth intrinsics that this intrinsic is lowered into. The intent is that the deactivation symbol represents a field identifier.

This intrinsic is used to implement structure protection.

<a id="llvm-cond-loop-intrinsic"></a>

#### ‘`llvm.cond.loop`’ Intrinsic

<a id="id2006"></a>

##### Syntax:

    declare void @llvm.cond.loop(i1 pred)

<a id="id2007"></a>

##### Overview:

The ‘`llvm.cond.loop`’ intrinsic spins in an infinite loop if the given predicate `pred` is true, otherwise it does nothing.

<a id="id2008"></a>

##### Arguments:

`pred` is the predicate.

<a id="id2009"></a>

##### Semantics:

This intrinsic is semantically equivalent to a conditional branch conditioned on `pred` to a basic block consisting only of an unconditional branch to itself.

Unlike such a branch, certain backends guarantee that this intrinsic will use specific instructions. This allows an interrupt handler or other introspection mechanism to straightforwardly detect whether the program is currently spinning in the infinite loop and possibly terminate the program if so. The intent is that this intrinsic may be used as a more efficient alternative to a conditional branch to a call to `llvm.trap` in circumstances where the loop detection is guaranteed to be present. This construct has been experimentally determined to be executed more efficiently (when the branch is not taken) than a conditional branch to a trap instruction on AMD and older Intel microarchitectures, and is also more code size efficient by avoiding the need to emit a trap instruction and possibly a long branch instruction.

With the X86 backend, the infinite loop is guaranteed to consist of a short conditional branch instruction that branches to itself. Specifically, the first byte of the instruction will be between 0x70 and 0x7F, and the second byte will be 0xFE.

There are currently no guarantees about instructions used by other backends.

<a id="llvm-looptrap-intrinsic"></a>

#### ‘`llvm.looptrap`’ Intrinsic

<a id="id2010"></a>

##### Syntax:

    declare void @llvm.looptrap() cold noreturn nounwind

<a id="id2011"></a>

##### Overview:

The ‘`llvm.looptrap`’ intrinsic is equivalent to `llvm.cond.loop(true)`, but is also considered to be `noreturn`, which enables certain optimizations by allowing the optimizer to assume that a branch leading to a call to this intrinsic was not taken. A late optimization pass will convert this intrinsic to either `llvm.cond.loop(true)` or `llvm.cond.loop(pred)`, where `pred` is a predicate for a conditional branch leading to the intrinsic call, if possible.
