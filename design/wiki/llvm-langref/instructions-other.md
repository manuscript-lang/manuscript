[Wiki](../index.md) › [LLVM LangRef](index.md)

# Other operations

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="other-operations"></a>

<a id="otherops"></a>

### Other Operations

The instructions in this category are the “miscellaneous” instructions, which defy better classification.

<a id="icmp-instruction"></a>

<a id="i-icmp"></a>

#### ‘`icmp`’ Instruction

<a id="id309"></a>

##### Syntax:

    <result> = icmp <cond> <ty> <op1>, <op2>   ; yields i1 or <N x i1>:result
    <result> = icmp samesign <cond> <ty> <op1>, <op2>   ; yields i1 or <N x i1>:result

<a id="id310"></a>

##### Overview:

The ‘`icmp`’ instruction returns a boolean value or a vector of boolean values based on comparison of its two integer, integer vector, pointer, or pointer vector operands.

<a id="id311"></a>

##### Arguments:

The ‘`icmp`’ instruction takes three operands. The first operand is the condition code indicating the kind of comparison to perform. It is not a value, just a keyword. The possible condition codes are:

1.  `eq`: equal

2.  `ne`: not equal

3.  `ugt`: unsigned greater than

4.  `uge`: unsigned greater or equal

5.  `ult`: unsigned less than

6.  `ule`: unsigned less or equal

7.  `sgt`: signed greater than

8.  `sge`: signed greater or equal

9.  `slt`: signed less than

10. `sle`: signed less or equal

The remaining two arguments must be [integer](type-system.md#t-integer) or [pointer](type-system.md#t-pointer) or integer [vector](type-system.md#t-vector) typed. They must also be identical types.

<a id="id312"></a>

##### Semantics:

The ‘`icmp`’ compares `op1` and `op2` according to the condition code given as `cond`. The comparison performed always yields either an [i1](type-system.md#t-integer) or vector of `i1` result, as follows:

1.  `eq`: yields `true` if the operands are equal, `false` otherwise. No sign interpretation is necessary or performed.

2.  `ne`: yields `true` if the operands are unequal, `false` otherwise. No sign interpretation is necessary or performed.

3.  `ugt`: interprets the operands as unsigned values and yields `true` if `op1` is greater than `op2`.

4.  `uge`: interprets the operands as unsigned values and yields `true` if `op1` is greater than or equal to `op2`.

5.  `ult`: interprets the operands as unsigned values and yields `true` if `op1` is less than `op2`.

6.  `ule`: interprets the operands as unsigned values and yields `true` if `op1` is less than or equal to `op2`.

7.  `sgt`: interprets the operands as signed values and yields `true` if `op1` is greater than `op2`.

8.  `sge`: interprets the operands as signed values and yields `true` if `op1` is greater than or equal to `op2`.

9.  `slt`: interprets the operands as signed values and yields `true` if `op1` is less than `op2`.

10. `sle`: interprets the operands as signed values and yields `true` if `op1` is less than or equal to `op2`.

If the operands are [pointer](type-system.md#t-pointer) typed, the address bits of the pointers are compared as if they were integers. Non-address bits or external state are not compared. That is, `icmp` on pointers is equivalent to `icmp` on the `ptrtoaddr` of the pointers.

If the operands are integer vectors, then they are compared element by element. The result is an `i1` vector with the same number of elements as the values being compared. Otherwise, the result is an `i1`.

If the `samesign` keyword is present and the operands are not of the same sign then the result is a [poison value](constants.md#poisonvalues).

<a id="id313"></a>

##### Example:

    <result> = icmp eq i32 4, 5          ; yields: result=false
    <result> = icmp ne ptr %X, %X        ; yields: result=false
    <result> = icmp ult i16  4, 5        ; yields: result=true
    <result> = icmp sgt i16  4, 5        ; yields: result=false
    <result> = icmp ule i16 -4, 5        ; yields: result=false
    <result> = icmp sge i16  4, 5        ; yields: result=false

<a id="fcmp-instruction"></a>

<a id="i-fcmp"></a>

#### ‘`fcmp`’ Instruction

<a id="id314"></a>

##### Syntax:

    <result> = fcmp [fast-math flags]* <cond> <ty> <op1>, <op2>     ; yields i1 or <N x i1>:result

<a id="id315"></a>

##### Overview:

The ‘`fcmp`’ instruction returns a boolean value or vector of boolean values based on comparison of its operands.

If the operands are floating-point scalars, then the result type is a boolean ([i1](type-system.md#t-integer)).

If the operands are floating-point vectors, then the result type is a vector of boolean with the same number of elements as the operands being compared.

<a id="id316"></a>

##### Arguments:

The ‘`fcmp`’ instruction takes three operands. The first operand is the condition code indicating the kind of comparison to perform. It is not a value, just a keyword. The possible condition codes are:

1.  `false`: no comparison, always returns false

2.  `oeq`: ordered and equal

3.  `ogt`: ordered and greater than

4.  `oge`: ordered and greater than or equal

5.  `olt`: ordered and less than

6.  `ole`: ordered and less than or equal

7.  `one`: ordered and not equal

8.  `ord`: ordered (no nans)

9.  `ueq`: unordered or equal

10. `ugt`: unordered or greater than

11. `uge`: unordered or greater than or equal

12. `ult`: unordered or less than

13. `ule`: unordered or less than or equal

14. `une`: unordered or not equal

15. `uno`: unordered (either nans)

16. `true`: no comparison, always returns true

*Ordered* means that neither operand is a QNAN while *unordered* means that either operand may be a QNAN.

Each of `val1` and `val2` arguments must be either a [floating-point](type-system.md#t-floating) type or a [vector](type-system.md#t-vector) of floating-point type. They must have identical types.

<a id="id317"></a>

##### Semantics:

The ‘`fcmp`’ instruction compares `op1` and `op2` according to the condition code given as `cond`. If the operands are vectors, then the vectors are compared element by element. Each comparison performed always yields an [i1](type-system.md#t-integer) result, as follows:

1.  `false`: always yields `false`, regardless of operands.

2.  `oeq`: yields `true` if both operands are not a QNAN and `op1` is equal to `op2`.

3.  `ogt`: yields `true` if both operands are not a QNAN and `op1` is greater than `op2`.

4.  `oge`: yields `true` if both operands are not a QNAN and `op1` is greater than or equal to `op2`.

5.  `olt`: yields `true` if both operands are not a QNAN and `op1` is less than `op2`.

6.  `ole`: yields `true` if both operands are not a QNAN and `op1` is less than or equal to `op2`.

7.  `one`: yields `true` if both operands are not a QNAN and `op1` is not equal to `op2`.

8.  `ord`: yields `true` if both operands are not a QNAN.

9.  `ueq`: yields `true` if either operand is a QNAN or `op1` is equal to `op2`.

10. `ugt`: yields `true` if either operand is a QNAN or `op1` is greater than `op2`.

11. `uge`: yields `true` if either operand is a QNAN or `op1` is greater than or equal to `op2`.

12. `ult`: yields `true` if either operand is a QNAN or `op1` is less than `op2`.

13. `ule`: yields `true` if either operand is a QNAN or `op1` is less than or equal to `op2`.

14. `une`: yields `true` if either operand is a QNAN or `op1` is not equal to `op2`.

15. `uno`: yields `true` if either operand is a QNAN.

16. `true`: always yields `true`, regardless of operands.

The `fcmp` instruction can also optionally take any number of [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations.

Any set of fast-math flags are legal on an `fcmp` instruction, but the only flags that have any effect on its semantics are those that allow assumptions to be made about the values of input arguments; namely `nnan`, `ninf`, and `reassoc`. See [Fast-Math Flags](high-level-structure.md#fastmath) for more information.

<a id="id318"></a>

##### Example:

    <result> = fcmp oeq float 4.0, 5.0    ; yields: result=false
    <result> = fcmp one float 4.0, 5.0    ; yields: result=true
    <result> = fcmp olt float 4.0, 5.0    ; yields: result=true
    <result> = fcmp ueq double 1.0, 2.0   ; yields: result=false

<a id="phi-instruction"></a>

<a id="i-phi"></a>

#### ‘`phi`’ Instruction

<a id="id319"></a>

##### Syntax:

    <result> = phi [fast-math-flags] <ty> [ <val0>, <label0>], ...

<a id="id320"></a>

##### Overview:

The ‘`phi`’ instruction is used to implement the φ node in the SSA graph representing the function.

<a id="id321"></a>

##### Arguments:

The type of the incoming values is specified with the first type field. After this, the ‘`phi`’ instruction takes a list of pairs as arguments, with one pair for each predecessor basic block of the current block. Only values of [first class](type-system.md#t-firstclass) type may be used as the value arguments to the PHI node. Only labels may be used as the label arguments.

There must be no non-phi instructions between the start of a basic block and the PHI instructions: i.e., PHI instructions must be first in a basic block.

For the purposes of the SSA form, the use of each incoming value is deemed to occur on the edge from the corresponding predecessor block to the current block (but after any definition of an ‘`invoke`’ instruction’s return value on the same edge).

The optional `fast-math-flags` marker indicates that the phi has one or more [fast-math-flags](high-level-structure.md#fastmath). These are optimization hints to enable otherwise unsafe floating-point optimizations. Fast-math-flags are only valid for phis that return [supported floating-point types](#fastmath-return-types).

<a id="id322"></a>

##### Semantics:

At runtime, the ‘`phi`’ instruction logically takes on the value specified by the pair corresponding to the predecessor basic block that executed just prior to the current block.

<a id="id323"></a>

##### Example:

    Loop:       ; Infinite loop that counts from 0 on up...
      %indvar = phi i32 [ 0, %LoopHeader ], [ %nextindvar, %Loop ]
      %nextindvar = add i32 %indvar, 1
      br label %Loop

<a id="select-instruction"></a>

<a id="i-select"></a>

#### ‘`select`’ Instruction

<a id="id324"></a>

##### Syntax:

    <result> = select [fast-math flags] selty <cond>, <ty> <val1>, <ty> <val2>             ; yields ty

    selty is either i1 or {<N x i1>}

<a id="id325"></a>

##### Overview:

The ‘`select`’ instruction is used to choose one value based on a condition, without IR-level branching.

<a id="id326"></a>

##### Arguments:

The ‘`select`’ instruction requires an ‘i1’ value or a vector of ‘i1’ values indicating the condition, and two values of the same [first class](type-system.md#t-firstclass) type.

1.  The optional `fast-math flags` marker indicates that the select has one or more [fast-math flags](high-level-structure.md#fastmath). These are optimization hints to enable otherwise unsafe floating-point optimizations. Fast-math flags are only valid for selects that return [supported floating-point types](#fastmath-return-types). Note that the presence of value which would otherwise result in poison does not cause the result to be poison if the value is on the non-selected arm. If [fast-math flags](high-level-structure.md#fastmath) are present, they are only applied to the result, not both arms.

<a id="id327"></a>

##### Semantics:

If the condition is an i1 and it evaluates to 1, the instruction returns the first value argument; otherwise, it returns the second value argument. If the condition evaluates to `poison`, the instruction returns `poison`. If it evaluates to `undef`, the result is an `undef` representing the union of two value arguments (i.e., each use of this value can pick either value argument).

If the condition is a vector of i1, then the value arguments must be vectors of the same size, and the selection is done element by element.

If the condition is an i1 and the value arguments are vectors of the same size, then an entire vector is selected.

<a id="id328"></a>

##### Example:

    %X = select i1 true, i8 17, i8 42                   ; yields i8:17
    %Y = select nnan i1 true, float 0.0, float NaN      ; yields float:0.0
    %Z = select nnan i1 false, float 0.0, float NaN     ; yields float:poison

<a id="freeze-instruction"></a>

<a id="i-freeze"></a>

#### ‘`freeze`’ Instruction

<a id="id329"></a>

##### Syntax:

    <result> = freeze ty <val>    ; yields ty:result

<a id="id330"></a>

##### Overview:

The ‘`freeze`’ instruction is used to stop propagation of [undef](constants.md#undefvalues) and [poison](constants.md#poisonvalues) values.

<a id="id331"></a>

##### Arguments:

The ‘`freeze`’ instruction takes a single argument.

<a id="id332"></a>

##### Semantics:

If the argument is `undef` or `poison`, ‘`freeze`’ returns an arbitrary, but fixed, value of type ‘`ty`’. Otherwise, this instruction is a no-op and returns the input argument. All uses of a value returned by the same ‘`freeze`’ instruction are guaranteed to always observe the same value, while different ‘`freeze`’ instructions may yield different values.

While `undef` and `poison` pointers can be frozen, the result is a non-dereferenceable pointer. See the [Pointer Aliasing Rules](high-level-structure.md#pointeraliasing) section for more information. Values of the [byte type](type-system.md#t-byte) are frozen on a per-bit basis. If an aggregate value or vector is frozen, the operand is frozen element-wise. The padding of an aggregate isn’t considered, since it isn’t visible without storing it into memory and loading it with a different type.

<a id="id333"></a>

##### Example:

    %w = i32 undef
    %x = freeze i32 %w
    %y = add i32 %w, %w         ; undef
    %z = add i32 %x, %x         ; even number because all uses of %x observe
                                ; the same value
    %x2 = freeze i32 %w
    %cmp = icmp eq i32 %x, %x2  ; can be true or false

    ; example with vectors
    %v = <2 x i32> <i32 undef, i32 poison>
    %a = extractelement <2 x i32> %v, i64 0    ; undef
    %b = extractelement <2 x i32> %v, i64 1    ; poison
    %add = add i32 %a, %a                      ; undef

    %v.fr = freeze <2 x i32> %v                ; element-wise freeze
    %d = extractelement <2 x i32> %v.fr, i64 0 ; not undef
    %add.f = add i32 %d, %d                    ; even number

    %l = load b32, ptr %p                      ; may be uninitialized
    %f = freeze b32 %l                         ; freezes on a per-bit basis

    ; branching on frozen value
    %poison = add nsw i1 %k, undef   ; poison
    %c = freeze i1 %poison
    br i1 %c, label %foo, label %bar ; non-deterministic branch to %foo or %bar

<a id="call-instruction"></a>

<a id="i-call"></a>

#### ‘`call`’ Instruction

<a id="id334"></a>

##### Syntax:

    <result> = [tail | musttail | notail ] call [fast-math flags] [cconv] [ret attrs] [addrspace(<num>)]
               <ty>|<fnty> <fnptrval>(<function args>) [fn attrs] [ operand bundles ]

<a id="id335"></a>

##### Overview:

The ‘`call`’ instruction represents a simple function call.

<a id="id336"></a>

##### Arguments:

This instruction requires several arguments:

1.  The optional `tail` and `musttail` markers indicate that the optimizers should perform tail call optimization. The `tail` marker is a hint that [can be ignored](CodeGenerator.html#tail-call-section). The `musttail` marker means that the call must be tail call optimized in order for the program to be correct. This is true even in the presence of attributes like “disable-tail-calls”. The `musttail` marker provides these guarantees:

    - The call will not cause unbounded stack growth if it is part of a recursive cycle in the call graph.

    - Arguments with the [inalloca](high-level-structure.md#attr-inalloca) or [preallocated](high-level-structure.md#attr-preallocated) attribute are forwarded in place.

    - If the musttail call appears in a function with the `"thunk"` attribute and the caller and callee both have varargs, then any unprototyped arguments in register or memory are forwarded to the callee. Similarly, the return value of the callee is returned to the caller’s caller, even if a void return type is in use.

    Both markers imply that the callee does not access allocas, va_args, or byval arguments from the caller. As an exception to that, an alloca or byval argument may be passed to the callee as a byval argument, which can be dereferenced inside the callee. For example:

    
    
        declare void @take_byval(ptr byval(i64))
        declare void @take_ptr(ptr)

        ; Invalid (assuming @take_ptr dereferences the pointer), because %local
        ; may be de-allocated before the call to @take_ptr.
        define void @invalid_alloca() {
        entry:
          %local = alloca i64
          tail call void @take_ptr(ptr %local)
          ret void
        }

        ; Valid, the byval attribute causes the memory allocated by %local to be
        ; copied into @take_byval's stack frame.
        define void @byval_alloca() {
        entry:
          %local = alloca i64
          tail call void @take_byval(ptr byval(i64) %local)
          ret void
        }

        ; Invalid, because @use_global_va_list uses the variadic arguments from
        ; @invalid_va_list.
        %struct.va_list = type { ptr }
        @va_list = external global %struct.va_list
        define void @use_global_va_list() {
        entry:
          %arg = va_arg ptr @va_list, i64
          ret void
        }
        define void @invalid_va_list(i32 %a, ...) {
        entry:
          call void @llvm.va_start.p0(ptr @va_list)
          tail call void @use_global_va_list()
          ret void
        }

        ; Valid, byval argument forwarded to tail call as another byval argument.
        define void @forward_byval(ptr byval(i64) %x) {
        entry:
          tail call void @take_byval(ptr byval(i64) %x)
          ret void
        }

        ; Invalid (assuming @take_ptr dereferences the pointer), byval argument
        ; passed to tail callee as non-byval ptr.
        define void @invalid_byval(ptr byval(i64) %x) {
        entry:
          tail call void @take_ptr(ptr %x)
          ret void
        }

    
    
    Calls marked `musttail` must obey the following additional rules:

    - The call must immediately precede a [ret](instructions-terminators.md#i-ret) instruction, or a pointer bitcast followed by a ret instruction.

    - The ret instruction must return the (possibly bitcasted) value produced by the call, undef, or void.

    - The calling conventions of the caller and callee must match.

    - The callee must be varargs iff the caller is varargs. Bitcasting a non-varargs function to the appropriate varargs type is legal so long as the non-varargs prefixes obey the other rules.

    - The return type must not undergo automatic conversion to an `sret` pointer.

    In addition, if the calling convention is not `swifttailcc` or `tailcc`:

    - All ABI-impacting function attributes, such as sret, byval, inreg, returned, and inalloca, must match.

    - The caller and callee prototypes must match. Pointer types of parameters or return types do not differ in address space.

    On the other hand, if the calling convention is `swifttailcc` or `tailcc`:

    - Only these ABI-impacting attributes attributes are allowed: sret, byval, swiftself, and swiftasync.

    - Prototypes are not required to match.

    Tail call optimization for calls marked `tail` is guaranteed to occur if the following conditions are met:

    - Caller and callee both have the calling convention `fastcc` or `tailcc`.

    - The call is in tail position (ret immediately follows call and ret uses value of call or is void).

    - Option `-tailcallopt` is enabled, `llvm::GuaranteedTailCallOpt` is `true`, or the calling convention is `tailcc`.

    - [Platform-specific constraints are met.](CodeGenerator.html#tail-call-section)

2.  The optional `notail` marker indicates that the optimizers should not add `tail` or `musttail` markers to the call. It is used to prevent tail call optimization from being performed on the call.

3.  The optional `fast-math flags` marker indicates that the call has one or more [fast-math flags](high-level-structure.md#fastmath), which are optimization hints to enable otherwise unsafe floating-point optimizations. Fast-math flags are only valid for calls that return [supported floating-point types](#fastmath-return-types).

4.  The optional “cconv” marker indicates which [calling convention](high-level-structure.md#callingconv) the call should use. If none is specified, the call defaults to using C calling conventions. The calling convention of the call must match the calling convention of the target function, or else the behavior is undefined.

5.  The optional [Parameter Attributes](high-level-structure.md#paramattrs) list for return values. Only ‘`zeroext`’, ‘`signext`’, ‘`noext`’, and ‘`inreg`’ attributes are valid here.

6.  The optional addrspace attribute can be used to indicate the address space of the called function. If it is not specified, the program address space from the [datalayout string](high-level-structure.md#langref-datalayout) will be used.

7.  ‘`ty`’: the type of the call instruction itself which is also the type of the return value. Functions that return no value are marked `void`. The signature is computed based on the return type and argument types.

8.  ‘`fnty`’: shall be the signature of the function being called. The argument types must match the types implied by this signature. This is only required if the signature specifies a varargs type.

9.  ‘`fnptrval`’: An LLVM value containing a pointer to a function to be called. In most cases, this is a direct function call, but indirect `call`’s are just as possible, calling an arbitrary pointer to function value.

10. ‘`function args`’: argument list whose types match the function signature argument types and parameter attributes. All arguments must be of [first class](type-system.md#t-firstclass) type. If the function signature indicates the function accepts a variable number of arguments, the extra arguments can be specified.

11. The optional [function attributes](high-level-structure.md#fnattrs) list.

12. The optional [operand bundles](high-level-structure.md#opbundles) list.

<a id="id337"></a>

##### Semantics:

The ‘`call`’ instruction is used to cause control flow to transfer to a specified function, with its incoming arguments bound to the specified values. Upon a ‘`ret`’ instruction in the called function, control flow continues with the instruction after the function call, and the return value of the function is bound to the result argument.

If the callee refers to an intrinsic function, the signature of the call must match the signature of the callee. Otherwise, if the signature of the call does not match the signature of the called function, the behavior is target-specific. For a significant mismatch, this likely results in undefined behavior. LLVM interprocedural optimizations generally only optimize calls where the signature of the caller matches the signature of the callee.

Note that it is possible for the signatures to mismatch even if a call appears to be a “direct” call, like `call void @f()`.

<a id="id338"></a>

##### Example:

    %retval = call i32 @test(i32 %argc)
    call i32 (ptr, ...) @printf(ptr %msg, i32 12, i8 42)        ; yields i32
    %X = tail call i32 @foo()                                    ; yields i32
    %Y = tail call fastcc i32 @foo()  ; yields i32
    call void %foo(i8 signext 97)

    %struct.A = type { i32, i8 }
    %r = call %struct.A @foo()                        ; yields { i32, i8 }
    %gr = extractvalue %struct.A %r, 0                ; yields i32
    %gr1 = extractvalue %struct.A %r, 1               ; yields i8
    %Z = call void @foo() noreturn                    ; indicates that %foo never returns normally
    %ZZ = call zeroext i32 @bar()                     ; Return value is %zero extended

llvm treats calls to some functions with names and arguments that match the standard C99 library as being the C99 library functions, and may perform optimizations or generate code for them under that assumption. This implies that undefined behavior in C standard library functions recognized by LLVM is also undefined behavior at the IR level.

<a id="va-arg-instruction"></a>

<a id="i-va-arg"></a>

#### ‘`va_arg`’ Instruction

<a id="id339"></a>

##### Syntax:

    <resultval> = va_arg <va_list*> <arglist>, <argty>

<a id="id340"></a>

##### Overview:

The ‘`va_arg`’ instruction is used to access arguments passed through the “variable argument” area of a function call. It is used to implement the `va_arg` macro in C.

<a id="id341"></a>

##### Arguments:

This instruction takes a `va_list*` value and the type of the argument. It returns a value of the specified argument type and increments the `va_list` to point to the next argument. The actual type of `va_list` is target specific.

<a id="id342"></a>

##### Semantics:

The ‘`va_arg`’ instruction loads an argument of the specified type from the specified `va_list` and causes the `va_list` to point to the next argument. For more information, see the variable argument handling [Intrinsic Functions](intrinsics-overview-and-basic.md#int-varargs).

It is legal for this instruction to be called in a function which does not take a variable number of arguments, for example, the `vfprintf` function.

`va_arg` is an LLVM instruction instead of an [intrinsic function](intrinsics-overview-and-basic.md#intrinsics) because it takes a type as an argument.

<a id="id343"></a>

##### Example:

See the [variable argument processing](intrinsics-overview-and-basic.md#int-varargs) section.

Note that the code generator does not yet fully support `va_arg` on many targets. Also, it does not currently support `va_arg` with aggregate types on any target.

<a id="landingpad-instruction"></a>

<a id="i-landingpad"></a>

#### ‘`landingpad`’ Instruction

<a id="id344"></a>

##### Syntax:

    <resultval> = landingpad <resultty> <clause>+
    <resultval> = landingpad <resultty> cleanup <clause>*

    <clause> := catch <type> <value>
    <clause> := filter <array constant type> <array constant>

<a id="id345"></a>

##### Overview:

The ‘`landingpad`’ instruction is used by [LLVM’s exception handling system](ExceptionHandling.html#overview) to specify that a basic block is a landing pad — one where the exception lands, and corresponds to the code found in the `catch` portion of a `try`/`catch` sequence. It defines values supplied by the [personality function](high-level-structure.md#personalityfn) upon re-entry to the function. The `resultval` has the type `resultty`.

<a id="id346"></a>

##### Arguments:

The optional `cleanup` flag indicates that the landing pad block is a cleanup.

A `clause` begins with the clause type — `catch` or `filter` — and contains the global variable representing the “type” that may be caught or filtered respectively. Unlike the `catch` clause, the `filter` clause takes an array constant as its argument. Use “`[0 x ptr] undef`” for a filter which cannot throw. The ‘`landingpad`’ instruction must contain *at least* one `clause` or the `cleanup` flag.

<a id="id347"></a>

##### Semantics:

The ‘`landingpad`’ instruction defines the values which are set by the [personality function](high-level-structure.md#personalityfn) upon re-entry to the function, and therefore the “result type” of the `landingpad` instruction. As with calling conventions, how the personality function results are represented in LLVM IR is target specific.

The clauses are applied in order from top to bottom. If two `landingpad` instructions are merged together through inlining, the clauses from the calling function are appended to the list of clauses. When the call stack is being unwound due to an exception being thrown, the exception is compared against each `clause` in turn. If it doesn’t match any of the clauses, and the `cleanup` flag is not set, then unwinding continues further up the call stack.

The `landingpad` instruction has several restrictions:

- A landing pad block is a basic block which is the unwind destination of an ‘`invoke`’ instruction.

- A landing pad block must have a ‘`landingpad`’ instruction as its first non-PHI instruction.

- There can be only one ‘`landingpad`’ instruction within the landing pad block.

- A basic block that is not a landing pad block may not include a ‘`landingpad`’ instruction.

<a id="id348"></a>

##### Example:

    ;; A landing pad which can catch an integer.
    %res = landingpad { ptr, i32 }
             catch ptr @_ZTIi
    ;; A landing pad that is a cleanup.
    %res = landingpad { ptr, i32 }
             cleanup
    ;; A landing pad which can catch an integer and can only throw a double.
    %res = landingpad { ptr, i32 }
             catch ptr @_ZTIi
             filter [1 x ptr] [ptr @_ZTId]

<a id="catchpad-instruction"></a>

<a id="i-catchpad"></a>

#### ‘`catchpad`’ Instruction

<a id="id349"></a>

##### Syntax:

    <resultval> = catchpad within <catchswitch> [<args>*]

<a id="id350"></a>

##### Overview:

The ‘`catchpad`’ instruction is used by [LLVM’s exception handling system](ExceptionHandling.html#overview) to specify that a basic block begins a catch handler — one where a personality routine attempts to transfer control to catch an exception.

<a id="id351"></a>

##### Arguments:

The `catchswitch` operand must always be a token produced by a [catchswitch](instructions-terminators.md#i-catchswitch) instruction in a predecessor block. This ensures that each `catchpad` has exactly one predecessor block, and it always terminates in a `catchswitch`.

The `args` correspond to whatever information the personality routine requires to determine if this is an appropriate handler for the exception. Each operand must be an alloca or a constant. Control will transfer to the `catchpad` if this is the first appropriate handler for the exception.

The `resultval` has the type [token](type-system.md#t-token) and is used to match the `catchpad` to corresponding [catchrets](instructions-terminators.md#i-catchret) and other nested EH pads.

<a id="id352"></a>

##### Semantics:

When the call stack is being unwound due to an exception being thrown, the exception is compared against the `args`. If it doesn’t match, control will not reach the `catchpad` instruction. The representation of `args` is entirely target and personality function-specific.

Like the [landingpad](#i-landingpad) instruction, the `catchpad` instruction must be the first non-phi of its parent basic block.

The meaning of the tokens produced and consumed by `catchpad` and other “pad” instructions is described in the [Windows exception handling documentation](ExceptionHandling.html#wineh).

When a `catchpad` has been “entered” but not yet “exited” (as described in the [EH documentation](ExceptionHandling.html#wineh-constraints)), it is undefined behavior to execute a [call](#i-call) or [invoke](instructions-terminators.md#i-invoke) that does not carry an appropriate [“funclet” bundle](high-level-structure.md#ob-funclet).

<a id="id353"></a>

##### Example:

    dispatch:
      %cs = catchswitch within none [label %handler0] unwind to caller
      ;; A catch block which can catch an integer.
    handler0:
      %tok = catchpad within %cs [ptr @_ZTIi]

<a id="cleanuppad-instruction"></a>

<a id="i-cleanuppad"></a>

#### ‘`cleanuppad`’ Instruction

<a id="id354"></a>

##### Syntax:

    <resultval> = cleanuppad within <parent> [<args>*]

<a id="id355"></a>

##### Overview:

The ‘`cleanuppad`’ instruction is used by [LLVM’s exception handling system](ExceptionHandling.html#overview) to specify that a basic block is a cleanup block — one where a personality routine attempts to transfer control to run cleanup actions. The `args` correspond to whatever additional information the [personality function](high-level-structure.md#personalityfn) requires to execute the cleanup. The `resultval` has the type [token](type-system.md#t-token) and is used to match the `cleanuppad` to corresponding [cleanuprets](instructions-terminators.md#i-cleanupret). The `parent` argument is the token of the funclet that contains the `cleanuppad` instruction. If the `cleanuppad` is not inside a funclet, this operand may be the token `none`.

<a id="id356"></a>

##### Arguments:

The instruction takes a list of arbitrary values which are interpreted by the [personality function](high-level-structure.md#personalityfn).

<a id="id357"></a>

##### Semantics:

When the call stack is being unwound due to an exception being thrown, the [personality function](high-level-structure.md#personalityfn) transfers control to the `cleanuppad` with the aid of the personality-specific arguments. As with calling conventions, how the personality function results are represented in LLVM IR is target specific.

The `cleanuppad` instruction has several restrictions:

- A cleanup block is a basic block which is the unwind destination of an exceptional instruction.

- A cleanup block must have a ‘`cleanuppad`’ instruction as its first non-PHI instruction.

- There can be only one ‘`cleanuppad`’ instruction within the cleanup block.

- A basic block that is not a cleanup block may not include a ‘`cleanuppad`’ instruction.

When a `cleanuppad` has been “entered” but not yet “exited” (as described in the [EH documentation](ExceptionHandling.html#wineh-constraints)), it is undefined behavior to execute a [call](#i-call) or [invoke](instructions-terminators.md#i-invoke) that does not carry an appropriate [“funclet” bundle](high-level-structure.md#ob-funclet).

<a id="id358"></a>

##### Example:

    %tok = cleanuppad within %cs []
